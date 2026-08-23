#!/usr/bin/env python3
"""
vision_worker.py - Local vision/OCR worker for MCP context artifacts.

The worker reads PNG/JPEG artifacts directly from the local context directory.
MCP never transports image bytes. In server mode one long-lived process accepts
newline-delimited JSON jobs over localhost and returns compact JSON responses.

CLI examples:
    python vision_worker.py --artifact <path>
    python vision_worker.py --artifact <path> --find-color "#FF0000"
    python vision_worker.py --compare <path_a> <path_b>
    python vision_worker.py --serve --context-root <absolute-path>
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import struct
import subprocess
import sys
import zlib
from pathlib import Path
from typing import Any


def decode_png(filepath: str | Path) -> tuple[int, int, list[list[tuple[int, int, int, int]]]]:
    """Minimal RGBA PNG decoder. Returns width, height and pixels."""
    with open(filepath, "rb") as f:
        data = f.read()

    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Not a PNG file")
    pos = 8
    width = height = 0
    raw_data = bytearray()
    color_type = 0
    bit_depth = 0
    while pos + 12 <= len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        chunk_type = data[pos + 4 : pos + 8]
        chunk_data = data[pos + 8 : pos + 8 + length]
        if chunk_type == b"IHDR":
            width = struct.unpack(">I", chunk_data[:4])[0]
            height = struct.unpack(">I", chunk_data[4:8])[0]
            bit_depth = chunk_data[8]
            color_type = chunk_data[9]
        elif chunk_type == b"IDAT":
            raw_data.extend(chunk_data)
        elif chunk_type == b"IEND":
            break
        pos += 12 + length

    if width == 0 or height == 0:
        raise ValueError("Could not read PNG dimensions")
    if bit_depth != 8 or color_type not in (6, 2):
        raise ValueError("Only 8-bit RGB/RGBA PNGs are supported")

    channels = 4 if color_type == 6 else 3
    decompressed = zlib.decompress(bytes(raw_data))
    stride = 1 + width * channels
    pixels: list[list[tuple[int, int, int, int]]] = []
    previous = bytearray(width * channels)

    for y in range(height):
        row_start = y * stride
        filt = decompressed[row_start]
        row_raw = bytearray(decompressed[row_start + 1 : row_start + stride])
        if len(row_raw) != width * channels:
            raise ValueError("Invalid PNG scanline")
        if filt == 1:
            for i in range(channels, len(row_raw)):
                row_raw[i] = (row_raw[i] + row_raw[i - channels]) & 0xFF
        elif filt == 2:
            for i in range(len(row_raw)):
                row_raw[i] = (row_raw[i] + previous[i]) & 0xFF
        elif filt == 3:
            for i in range(len(row_raw)):
                left = row_raw[i - channels] if i >= channels else 0
                row_raw[i] = (row_raw[i] + (left + previous[i]) // 2) & 0xFF
        elif filt == 4:
            for i in range(len(row_raw)):
                left = row_raw[i - channels] if i >= channels else 0
                up = previous[i]
                up_left = previous[i - channels] if i >= channels else 0
                p = left + up - up_left
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - up_left)
                predictor = left if pa <= pb and pa <= pc else (up if pb <= pc else up_left)
                row_raw[i] = (row_raw[i] + predictor) & 0xFF
        elif filt != 0:
            raise ValueError(f"Unsupported PNG filter {filt}")

        row: list[tuple[int, int, int, int]] = []
        for x in range(0, len(row_raw), channels):
            if channels == 4:
                row.append((row_raw[x], row_raw[x + 1], row_raw[x + 2], row_raw[x + 3]))
            else:
                row.append((row_raw[x], row_raw[x + 1], row_raw[x + 2], 255))
        pixels.append(row)
        previous = row_raw
    return width, height, pixels


def _safe_context_id(context_id: str) -> str:
    if not context_id or context_id in (".", ".."):
        raise ValueError("Invalid context id")
    if any(ch not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-" for ch in context_id):
        raise ValueError("Invalid context id")
    return context_id


def artifact_from_context(context_root: str | Path, context_id: str) -> Path:
    root = Path(context_root).resolve()
    safe_id = _safe_context_id(context_id)
    metadata_path = root / f"{safe_id}.json"
    if not metadata_path.is_file():
        raise FileNotFoundError(f"Context metadata not found: {safe_id}")
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    relative = str(metadata.get("worker_path", metadata.get("path", "")))
    extension = Path(relative).suffix.lower() or ".png"
    if extension not in (".png", ".jpg", ".jpeg"):
        raise ValueError("Unsupported artifact format")
    artifact = (root / f"{safe_id}{extension}").resolve()
    if root not in artifact.parents:
        raise ValueError("Artifact escaped context root")
    if not artifact.is_file():
        raise FileNotFoundError(f"Context image not found: {safe_id}")
    return artifact


def palette(pixels: list[list[tuple[int, int, int, int]]], width: int, height: int, limit: int = 8) -> list[str]:
    counts: dict[str, int] = {}
    step = max(1, min(width, height) // 24)
    for y in range(0, height, step):
        for x in range(0, width, step):
            r, g, b, _ = pixels[y][x]
            key = f"#{r:02x}{g:02x}{b:02x}"
            counts[key] = counts.get(key, 0) + 1
    return [key for key, _ in sorted(counts.items(), key=lambda pair: pair[1], reverse=True)[:limit]]


def find_color_pixels(
    pixels: list[list[tuple[int, int, int, int]]],
    width: int,
    height: int,
    target_hex: str,
    tolerance: float,
    all_matches: bool = False,
) -> dict[str, Any]:
    target = target_hex.lstrip("#")
    if len(target) != 6:
        raise ValueError("Color must be #RRGGBB")
    tr, tg, tb = int(target[0:2], 16), int(target[2:4], 16), int(target[4:6], 16)
    limit = max(0.0, tolerance) * 255.0
    matches = 0
    first: dict[str, Any] | None = None
    for y in range(height):
        for x in range(width):
            r, g, b, _ = pixels[y][x]
            if abs(r - tr) <= limit and abs(g - tg) <= limit and abs(b - tb) <= limit:
                matches += 1
                if first is None:
                    first = {"x": x, "y": y, "rgb": [r, g, b]}
                if not all_matches:
                    return {"found": True, "matches": 1, "first": first}
    return {"found": matches > 0, "matches": matches, "first": first}


def detect_rects(pixels: list[list[tuple[int, int, int, int]]], width: int, height: int) -> list[dict[str, int]]:
    edges: list[dict[str, int]] = []
    row_step = max(1, height // 20)
    for y in range(0, height, row_step):
        prev_lum = -1.0
        edge_start = 0
        for x in range(1, width, 4):
            r, g, b, _ = pixels[y][x]
            lum = (r + g + b) / (3 * 255)
            if prev_lum >= 0 and abs(lum - prev_lum) > 0.15:
                if edge_start:
                    rw = x - edge_start
                    if 40 <= rw <= 600:
                        edges.append({"x": edge_start, "y": y, "w": rw, "h": row_step})
                    edge_start = 0
                else:
                    edge_start = x
            prev_lum = lum
    return edges[:128]


def compare_pixels(
    first: list[list[tuple[int, int, int, int]]],
    second: list[list[tuple[int, int, int, int]]],
    width: int,
    height: int,
) -> dict[str, Any]:
    sample_step = max(1, min(width, height) // 480)
    changed = 0
    total = 0
    for y in range(0, height, sample_step):
        for x in range(0, width, sample_step):
            total += 1
            a, b = first[y][x], second[y][x]
            if max(abs(a[i] - b[i]) for i in range(3)) > 5:
                changed += 1
    return {
        "changed_pixels": changed,
        "sampled_pixels": total,
        "change_ratio": changed / total if total else 0.0,
        "stable": changed == 0,
    }


def run_ocr(path: Path, command: str) -> dict[str, Any]:
    if not command:
        return {"available": False, "text": "", "reason": "ocr command not configured"}
    try:
        result = subprocess.run(
            [command, str(path), "stdout", "--psm", "6"],
            capture_output=True,
            text=True,
            timeout=12,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"available": False, "text": "", "reason": str(exc)}
    if result.returncode != 0:
        return {"available": False, "text": "", "reason": result.stderr.strip()[:500]}
    return {"available": True, "text": result.stdout.strip()}


def analyze_artifact(path: Path, do_ocr: bool = False, ocr_command: str = "") -> dict[str, Any]:
    if path.suffix.lower() != ".png":
        return {"error": "Worker analysis currently supports PNG artifacts only"}
    width, height, pixels = decode_png(path)
    result: dict[str, Any] = {
        "width": width,
        "height": height,
        "palette": palette(pixels, width, height),
        "rects": detect_rects(pixels, width, height),
        "artifact": str(path),
    }
    if do_ocr:
        result["ocr"] = run_ocr(path, ocr_command)
    return result


def handle_job(job: dict[str, Any], context_root: str, ocr_command: str) -> dict[str, Any]:
    operation = str(job.get("operation", ""))
    try:
        if operation == "info":
            return {"ok": True, "worker": "vision_worker", "operations": ["analyze", "ocr", "compare", "info"]}
        if operation == "analyze":
            path = artifact_from_context(context_root, str(job.get("context_id", "")))
            return {"ok": True, "id": str(job.get("id", "")), **analyze_artifact(path, bool(job.get("ocr", False)), ocr_command)}
        if operation == "ocr":
            path = artifact_from_context(context_root, str(job.get("context_id", "")))
            return {"ok": True, "id": str(job.get("id", "")), "ocr": run_ocr(path, ocr_command)}
        if operation == "compare":
            first_path = artifact_from_context(context_root, str(job.get("context_a", "")))
            second_path = artifact_from_context(context_root, str(job.get("context_b", "")))
            if first_path.suffix.lower() != ".png" or second_path.suffix.lower() != ".png":
                return {"ok": False, "id": str(job.get("id", "")), "error": "Compare currently supports PNG artifacts only"}
            w1, h1, first = decode_png(first_path)
            w2, h2, second = decode_png(second_path)
            if (w1, h1) != (w2, h2):
                return {"ok": True, "id": str(job.get("id", "")), "size_mismatch": True, "first": [w1, h1], "second": [w2, h2]}
            return {"ok": True, "id": str(job.get("id", "")), **compare_pixels(first, second, w1, h1)}
        return {"ok": False, "id": str(job.get("id", "")), "error": f"Unknown operation: {operation}"}
    except Exception as exc:  # worker boundary: return errors to the MCP session
        return {"ok": False, "id": str(job.get("id", "")), "error": str(exc)}


def serve(args: argparse.Namespace) -> int:
    context_root = str(Path(args.context_root).resolve())
    Path(context_root).mkdir(parents=True, exist_ok=True)
    ocr_command = args.ocr_command or os.environ.get("MCP_OCR_COMMAND", "")
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((args.host, args.port))
        server.listen(1)
        server.settimeout(1.0)
        while True:
            try:
                connection, _address = server.accept()
            except socket.timeout:
                continue
            with connection:
                file = connection.makefile("rwb")
                for raw_line in file:
                    if not raw_line:
                        break
                    try:
                        job = json.loads(raw_line.decode("utf-8"))
                        response = handle_job(job, context_root, ocr_command)
                    except Exception as exc:
                        response = {"ok": False, "error": str(exc)}
                    file.write((json.dumps(response, separators=(",", ":")) + "\n").encode("utf-8"))
                    file.flush()
            # One supervisor owns this process. A new connection is accepted
            # after a client disconnects, without spawning another worker.
    return 0


def cmd_show_info(args: argparse.Namespace) -> None:
    width, height, _ = decode_png(args.artifact)
    print(f"PNG: {width}x{height}")


def cmd_find_color(args: argparse.Namespace) -> None:
    width, height, pixels = decode_png(args.artifact)
    result = find_color_pixels(pixels, width, height, args.find_color, args.tolerance, args.all)
    print(json.dumps(result) if args.json else result)


def cmd_detect_rects(args: argparse.Namespace) -> None:
    width, height, pixels = decode_png(args.artifact)
    result = detect_rects(pixels, width, height)
    print(json.dumps({"count": len(result), "rects": result}) if args.json else f"Detected {len(result)} candidate rects: {result[:12]}")


def cmd_compare(args: argparse.Namespace) -> None:
    w1, h1, first = decode_png(args.compare[0])
    w2, h2, second = decode_png(args.compare[1])
    if (w1, h1) != (w2, h2):
        print(f"Size mismatch: {w1}x{h1} vs {w2}x{h2}")
        return
    print(json.dumps(compare_pixels(first, second, w1, h1)))


def main() -> int:
    parser = argparse.ArgumentParser(description="Local MCP vision worker")
    parser.add_argument("--artifact", help="Path to PNG screenshot")
    parser.add_argument("--find-color", help="Find a hex color (#RRGGBB)")
    parser.add_argument("--tolerance", type=float, default=0.05)
    parser.add_argument("--all", action="store_true", help="Count all matching pixels")
    parser.add_argument("--detect-rects", action="store_true")
    parser.add_argument("--compare", nargs=2, help="Compare two PNGs")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--serve", action="store_true", help="Run the persistent localhost job server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9127)
    parser.add_argument("--context-root", default=".")
    parser.add_argument("--ocr-command", default="")
    args = parser.parse_args()

    if args.serve:
        return serve(args)
    try:
        if args.compare:
            cmd_compare(args)
        elif args.find_color:
            cmd_find_color(args)
        elif args.detect_rects:
            cmd_detect_rects(args)
        elif args.artifact:
            cmd_show_info(args)
        else:
            parser.print_help()
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
