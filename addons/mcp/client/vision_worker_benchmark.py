#!/usr/bin/env python3
"""Benchmark für den Python-Vision-Worker (Nachfolger des MCP_OCR_POOL-Vergleichs).

Der JS-Worker (tesseract.js, MCP_OCR_POOL) ist entfernt; OCR läuft jetzt als
ein Tesseract-Subprocess pro Job im Python-Worker. Dieser Benchmark misst die
AKTUELLE Architektur: Job-Latenz pro Operation + Burst-Durchsatz über die
threaded TCP-Serve-Loop.

Misst:
  * analyze-Jobs (Pillow-Pixelanalyse)          — Latenz min/avg/max
  * ocr-Jobs (Tesseract-CLI, falls installiert) — Latenz + availability
  * compare-Jobs (Pixel-Diff)                   — Latenz
  * Burst: 8Jobs parallel über einen Socket     — Wandzeit + Job/s

Aufruf:
  python vision_worker_benchmark.py [--width 640] [--height 400] [--burst 8]

Ergebnis: kompakte Tabelle auf stdout; Exit 0 immer (Messung, kein Gate).
"""
from __future__ import annotations

import io
import json
import pathlib
import socket
import statistics
import struct
import subprocess
import sys
import tempfile
import threading
import time
import zlib

HERE = pathlib.Path(__file__).resolve().parent
WORKER = HERE / "vision_worker.py"


# ---------------------------------------------------------------------------
# Synthetisches UI-PNG (stdlib-zlib + Pillow-Text, echte Glyphen für OCR)
# ---------------------------------------------------------------------------

def synth_ui_png(width: int, height: int) -> bytes:
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        raise SystemExit("Pillow fehlt (pip install Pillow) — Benchmark braucht echte Glyphen")

    img = Image.new("RGB", (width, height), (24, 26, 34))
    draw = ImageDraw.Draw(img)
    labels = [
        "NEUES SPIEL", "WEITERSPIELEN", "EINSTELLUNGEN", "BEENDEN",
        "FORSCHUNG", "WERKSTATT", "PLANET", "MISSON SENDING",
    ]
    y = 16
    for label in labels:
        draw.rectangle([20, y, width - 20, y + 34], outline=(120, 200, 130), width=2)
        draw.text((32, y + 8), label, fill=(230, 230, 220))
        y += 46
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def write_chunk(tag: bytes, payload: bytes) -> bytes:
    return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)


def raw_png_fallback(width: int, height: int) -> bytes:
    """Ohne Pillow: einfarbiges PNG (keine Glyphen, nur Pipeline-Messung)."""
    raw = b"".join(b"\x00" + b"\x18\x1a\x22" * width for _ in range(height))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + write_chunk(b"IHDR", ihdr)
            + write_chunk(b"IDAT", zlib.compress(raw, 6)) + write_chunk(b"IEND", b""))


# ---------------------------------------------------------------------------
# Worker-Client (ein Socket, newline-JSON wie der Runtime-Supervisor)
# ---------------------------------------------------------------------------

class WorkerClient:
    def __init__(self, port: int) -> None:
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=30)
        self.f = self.sock.makefile("r", encoding="utf-8", newline="\n")
        self.next_id = 0

    def call(self, operation: str, **args: object) -> dict:
        self.next_id += 1
        job = {"id": f"bench_{self.next_id}", "operation": operation, **args}
        self.sock.sendall((json.dumps(job) + "\n").encode("utf-8"))
        line = self.f.readline()
        if not line:
            raise RuntimeError("worker closed connection")
        return json.loads(line)

    def close(self) -> None:
        try:
            self.sock.close()
        except OSError:
            pass


def stats_block(latencies: list[float]) -> dict:
    if not latencies:
        return {"count": 0}
    return {
        "count": len(latencies),
        "min_ms": round(min(latencies), 1),
        "avg_ms": round(statistics.fmean(latencies), 1),
        "max_ms": round(max(latencies), 1),
    }


def main() -> None:
    width, height, burst = 640, 400, 8
    argv = sys.argv[1:]
    if "--width" in argv:
        width = int(argv[argv.index("--width") + 1])
    if "--height" in argv:
        height = int(argv[argv.index("--height") + 1])
    if "--burst" in argv:
        burst = int(argv[argv.index("--burst") + 1])

    try:
        png = synth_ui_png(width, height)
        mode = "pillow_text"
    except SystemExit:
        png = raw_png_fallback(width, height)
        mode = "solid_fallback"

    with tempfile.TemporaryDirectory(prefix="mcp_bench_") as tmp:
        root = pathlib.Path(tmp)
        # Vertragskonvention des Workers: Artifact-Dateiname = <context_id><ext>
        # (die Metadaten liefern nur die Endung — siehe artifact_from_context).
        png_path = root / "bench_ctx.png"
        png_path.write_bytes(png)
        (root / "bench_ctx.json").write_text(json.dumps({
            "worker_path": str(png_path), "path": str(png_path),
            "width": width, "height": height, "format": "png",
        }), encoding="utf-8")

        port = 9127
        try:
            with socket.socket() as probe:
                probe.bind(("127.0.0.1", port))
        except OSError:
            with socket.socket() as s:  # Port belegt → freien via OS wählen
                s.bind(("127.0.0.1", 0))
                port = int(s.getsockname()[1])

        proc = subprocess.Popen(
            [sys.executable, str(WORKER), "--serve", "--host", "127.0.0.1",
             "--port", str(port), "--context-root", str(root)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        try:
            for _ in range(50):
                try:
                    socket.create_connection(("127.0.0.1", port), timeout=0.2).close()
                    break
                except OSError:
                    time.sleep(0.1)
            else:
                raise RuntimeError("worker startete nicht")

            client = WorkerClient(port)
            info = client.call("info")
            print(f"worker: {info.get('worker')} ops={info.get('operations')} mode={mode} {width}x{height}")

            for op, kwargs in (("analyze", {"context_id": "bench_ctx"}),
                               ("ocr", {"context_id": "bench_ctx"}),
                               ("compare", {"context_a": "bench_ctx", "context_b": "bench_ctx"})):
                latencies: list[float] = []
                last: dict = {}
                ok_count = 0
                for _ in range(10):
                    t0 = time.perf_counter()
                    last = client.call(op, **kwargs)
                    latencies.append((time.perf_counter() - t0) * 1000.0)
                    if last.get("ok"):
                        ok_count += 1
                extra = f" ok={ok_count}/10"
                if op == "ocr":
                    ocr = last.get("ocr", {})
                    extra += f" available={ocr.get('available')}" + (
                        f" reason='{ocr.get('reason')}'" if not ocr.get("available") else f" text_chars={len(str(ocr.get('text', '')))}")
                elif not last.get("ok"):
                    extra += f" error='{last.get('error', '')}'"
                print(f"{op:8s} {stats_block(latencies)}{extra}")

            # Burst: N Jobs parallel, ein Socket pro Thread (wie Runtime MAX_PENDING=4)
            results: list[float] = []
            lock = threading.Lock()

            def burst_job() -> None:
                c = WorkerClient(port)
                t0 = time.perf_counter()
                r = c.call("analyze", context_id="bench_ctx")
                dt = (time.perf_counter() - t0) * 1000.0
                with lock:
                    results.append(dt)
                    if not r.get("ok"):
                        results.append(float("nan"))  # Fehler sichtbar machen: NaN ruiniert min/avg bewusst
                c.close()

            wall0 = time.perf_counter()
            threads = [threading.Thread(target=burst_job) for _ in range(burst)]
            for t in threads:
                t.start()
            for t in threads:
                t.join()
            wall_ms = (time.perf_counter() - wall0) * 1000.0
            print(f"burst    {stats_block(results)} wall_ms={round(wall_ms, 1)} jobs_per_s={round(len(results) / (wall_ms / 1000.0), 1)}")
            client.close()
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()

    print("Hinweis: OCR-Latenzen sind nur aussagekräftig, wenn die Tesseract-CLI installiert ist — sonst messen sie den Unavailable-Pfad (reason im ocr-Resultat).")


if __name__ == "__main__":
    main()
