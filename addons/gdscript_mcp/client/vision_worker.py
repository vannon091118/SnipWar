#!/usr/bin/env python3
"""Local MCP vision worker — Python port of vision_worker.js.

Reads PNG artifacts from one session-specific context directory and serves
compact JSON jobs over localhost. Image bytes never cross the MCP socket.

OCR is optional — requires either:
  * --ocr-command <path> (e.g. "tesseract" or "python -m pytesseract")
  * pytesseract Python package + Tesseract CLI installed

Otherwise OCR reports unavailable (same as the original JS version).

Dependencies:
  * Pillow (pip install Pillow) — for PNG/image analysis
  * stdlib only for TCP, JSON, subprocess
"""
from __future__ import annotations

import json
import os
import pathlib
import re
import socket
import subprocess
import sys
import threading
from typing import Any

try:
    from PIL import Image
except ImportError:
    Image = None  # type: ignore[assignment]

# ---------------------------------------------------------------------------
# CLI arguments
# ---------------------------------------------------------------------------

def parse_args(argv: list[str]) -> dict[str, Any]:
    result: dict[str, Any] = {
        "serve": False,
        "host": "127.0.0.1",
        "port": 9127,
        "context_root": ".",
        "ocr_command": "",
    }
    i = 1
    while i < len(argv):
        arg = argv[i]
        if arg == "--serve":
            result["serve"] = True
        elif arg == "--host" and i + 1 < len(argv):
            i += 1
            result["host"] = argv[i]
        elif arg == "--port" and i + 1 < len(argv):
            i += 1
            result["port"] = int(argv[i])
        elif arg == "--context-root" and i + 1 < len(argv):
            i += 1
            result["context_root"] = argv[i]
        elif arg == "--ocr-command" and i + 1 < len(argv):
            i += 1
            result["ocr_command"] = argv[i]
        i += 1
    return result


# ---------------------------------------------------------------------------
# Context artifact resolution
# ---------------------------------------------------------------------------

_SAFE_ID = re.compile(r"^[A-Za-z0-9_-]+$")


def safe_context_id(value: str) -> str:
    v = str(value or "")
    if not _SAFE_ID.match(v):
        raise ValueError(f"Invalid context id: {v!r}")
    return v


def artifact_from_context(context_root: str, context_id: str) -> pathlib.Path:
    root = pathlib.Path(context_root).resolve()
    cid = safe_context_id(context_id)

    # Metadata can be in root OR session subdirectories
    metadata_path = root / f"{cid}.json"
    if not metadata_path.exists():
        for entry in root.iterdir():
            if entry.is_dir():
                candidate = entry / f"{cid}.json"
                if candidate.exists():
                    metadata_path = candidate
                    break
    else:
        pass  # already found

    if not metadata_path.exists():
        raise FileNotFoundError(f"Context metadata not found: {cid}")

    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    ext = os.path.splitext(str(metadata.get("worker_path", metadata.get("path", ".png"))))[1].lower() or ".png"
    if ext not in (".png", ".jpg", ".jpeg"):
        raise ValueError(f"Unsupported artifact format: {ext}")

    artifact_dir = metadata_path.parent
    artifact = (artifact_dir / f"{cid}{ext}").resolve()

    # Security: artifact must stay within context root
    if not str(artifact).startswith(str(root)):
        raise ValueError("Artifact escaped context root")

    if not artifact.is_file():
        raise FileNotFoundError(f"Context image not found: {artifact}")

    return artifact


# ---------------------------------------------------------------------------
# Image analysis (Pillow)
# ---------------------------------------------------------------------------

def analyze_image(file_path: pathlib.Path) -> dict[str, Any]:
    if Image is None:
        raise RuntimeError("Pillow not installed (pip install Pillow)")

    img = Image.open(file_path).convert("RGBA")
    width, height = img.size

    # Dominant palette (sampled)
    palette: list[str] = []
    counts: dict[str, int] = {}
    step = max(1, min(width, height) // 24)
    pixels = img.load()
    if pixels is None:
        raise RuntimeError("Failed to load pixel data")

    for y in range(0, height, step):
        for x in range(0, width, step):
            r, g, b, _ = pixels[x, y]
            key = f"#{r:02x}{g:02x}{b:02x}"
            counts[key] = counts.get(key, 0) + 1

    sorted_colors = sorted(counts.items(), key=lambda kv: kv[1], reverse=True)
    palette = [c for c, _ in sorted_colors[:8]]

    # Rectangle detection (luminance edges)
    rects: list[dict[str, int]] = []
    row_step = max(1, height // 20)
    for y in range(0, height, row_step):
        prev_lum: float | None = None
        start = 0
        for x in range(1, width, 4):
            r, g, b, _ = pixels[x, y]
            lum = (r + g + b) / (3 * 255)
            if prev_lum is not None and abs(lum - prev_lum) > 0.15:
                if start:
                    w = x - start
                    if 40 <= w <= 600:
                        rects.append({"x": start, "y": y, "w": w, "h": row_step})
                    start = 0
                else:
                    start = x
            prev_lum = lum
    rects = rects[:128]

    return {
        "width": width,
        "height": height,
        "palette": palette,
        "rects": rects,
        "artifact": str(file_path),
    }


def compare_images(first_path: pathlib.Path, second_path: pathlib.Path) -> dict[str, Any]:
    if Image is None:
        raise RuntimeError("Pillow not installed (pip install Pillow)")

    img_a = Image.open(first_path).convert("RGB")
    img_b = Image.open(second_path).convert("RGB")

    if img_a.size != img_b.size:
        return {
            "size_mismatch": True,
            "first": list(img_a.size),
            "second": list(img_b.size),
        }

    w, h = img_a.size
    step = max(1, min(w, h) // 480)
    changed = 0
    sampled = 0
    px_a = img_a.load()
    px_b = img_b.load()
    if px_a is None or px_b is None:
        return {"changed_pixels": 0, "sampled_pixels": 0, "change_ratio": 0, "stable": True}

    for y in range(0, h, step):
        for x in range(0, w, step):
            sampled += 1
            ra, ga, ba = px_a[x, y][:3]
            rb, gb, bb = px_b[x, y][:3]
            if max(abs(ra - rb), abs(ga - gb), abs(ba - bb)) > 5:
                changed += 1

    return {
        "changed_pixels": changed,
        "sampled_pixels": sampled,
        "change_ratio": changed / sampled if sampled else 0,
        "stable": changed == 0,
    }


# ---------------------------------------------------------------------------
# OCR (optional)
# ---------------------------------------------------------------------------

def run_ocr(file_path: pathlib.Path, ocr_command: str) -> dict[str, Any]:
    """Run OCR on an image. Returns OCR result dict."""
    if not ocr_command:
        return {"available": False, "text": "", "reason": "No --ocr-command configured"}

    try:
        # Write to temp file, run command, read output
        result = subprocess.run(
            [ocr_command, str(file_path)],
            capture_output=True,
            text=True,
            timeout=60,
        )
        if result.returncode != 0:
            return {"available": False, "text": "", "reason": result.stderr.strip() or f"OCR command exited {result.returncode}"}

        text = result.stdout.strip()
        lines = [l.strip() for l in text.split("\n") if l.strip()]
        return {
            "available": True,
            "text": text,
            "lines": lines,
            "confidence": -1,  # unknown without tesseract API
        }
    except subprocess.TimeoutExpired:
        return {"available": False, "text": "", "reason": "OCR timed out (60s)"}
    except FileNotFoundError:
        return {"available": False, "text": "", "reason": f"OCR command not found: {ocr_command}"}
    except Exception as e:
        return {"available": False, "text": "", "reason": str(e)}


# ---------------------------------------------------------------------------
# Job dispatch
# ---------------------------------------------------------------------------

def handle_job(job: dict, context_root: str, ocr_command: str) -> dict:
    operation = str(job.get("operation", ""))
    job_id = str(job.get("id", ""))

    try:
        if operation == "info":
            return {
                "ok": True,
                "worker": "vision_worker_python",
                "operations": ["analyze", "ocr", "compare", "info"],
            }

        if operation == "analyze":
            artifact = artifact_from_context(context_root, job.get("context_id", ""))
            result = analyze_image(artifact)
            result["ok"] = True
            result["id"] = job_id
            return result

        if operation == "ocr":
            artifact = artifact_from_context(context_root, job.get("context_id", ""))
            ocr_result = run_ocr(artifact, ocr_command)
            return {"ok": True, "id": job_id, "ocr": ocr_result}

        if operation == "compare":
            first = artifact_from_context(context_root, job.get("context_a", ""))
            second = artifact_from_context(context_root, job.get("context_b", ""))
            result = compare_images(first, second)
            result["ok"] = True
            result["id"] = job_id
            return result

        return {"ok": False, "id": job_id, "error": f"Unknown operation: {operation}"}
    except Exception as e:
        return {"ok": False, "id": job_id, "error": str(e)}


# ---------------------------------------------------------------------------
# TCP serve loop
# ---------------------------------------------------------------------------

def serve(host: str, port: int, context_root: str, ocr_command: str) -> None:
    ctx = pathlib.Path(context_root).resolve()
    ctx.mkdir(parents=True, exist_ok=True)

    def handle_client(conn: socket.socket, addr: tuple) -> None:
        buffer = ""
        try:
            conn.settimeout(60)
            while True:
                try:
                    data = conn.recv(65536)
                except (socket.timeout, OSError):
                    break
                if not data:
                    break
                buffer += data.decode("utf-8", errors="replace")
                if len(buffer) > 1024 * 1024:
                    conn.close()
                    return
                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        parsed = json.loads(line)
                        response = handle_job(parsed, context_root, ocr_command)
                    except Exception as e:
                        response = {"ok": False, "error": str(e)}
                    try:
                        conn.sendall((json.dumps(response) + "\n").encode("utf-8"))
                    except OSError:
                        return
        finally:
            try:
                conn.close()
            except OSError:
                pass

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((host, port))
    server.listen(8)
    sys.stderr.write(f"[vision-worker-python] listening on {host}:{port}\n")
    sys.stderr.flush()

    try:
        while True:
            try:
                conn, addr = server.accept()
            except OSError:
                break
            t = threading.Thread(target=handle_client, args=(conn, addr), daemon=True)
            t.start()
    finally:
        server.close()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    args = parse_args(sys.argv)
    if args["serve"]:
        serve(args["host"], args["port"], args["context_root"], args["ocr_command"])
    else:
        sys.stderr.write(
            "Usage: vision_worker.py --serve --context-root <path> --port <port> "
            "[--ocr-command <cmd>]\n"
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
