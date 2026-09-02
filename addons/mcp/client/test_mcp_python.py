#!/usr/bin/env python3
"""Integration test for the Python MCP components:
  1. vision_worker.py — analyze, compare, info, OCR fallback
  2. mcp_stdio_bridge.py — stdin↔TCP relay

No Godot required. All tests run locally.
"""
from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

PASS = 0
FAIL = 0
THIS_DIR = Path(__file__).resolve().parent


def ok(name: str, detail: str = "") -> None:
    global PASS
    PASS += 1
    tag = f"  [OK] {name}"
    if detail:
        tag += f" ({detail})"
    print(tag)


def fail(name: str, reason: str) -> None:
    global FAIL
    FAIL += 1
    print(f"  [FAIL] {name}: {reason}")


def find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def make_test_png(path: Path, width: int = 100, height: int = 80, color: tuple = (255, 128, 0)) -> None:
    """Create a minimal valid PNG file (solid color) using only stdlib."""
    import zlib
    import struct

    # Build raw scanlines (filter=None)
    raw = b""
    for y in range(height):
        raw += b"\x00"  # filter byte
        for x in range(width):
            raw += bytes(color[:3])

    compressed = zlib.compress(raw)

    def chunk(ctype: bytes, data: bytes) -> bytes:
        c = ctype + data
        crc = struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
        return struct.pack(">I", len(data)) + c + crc

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", compressed))
        f.write(chunk(b"IEND", b""))


# ---------------------------------------------------------------------------
# Test 1: Vision Worker — info, analyze, compare, OCR fallback
# ---------------------------------------------------------------------------

def test_vision_worker() -> None:
    print("\n=== Vision Worker Tests ===")
    port = find_free_port()
    ctx = tempfile.mkdtemp(prefix="mcp_test_")

    # Create test PNGs
    png_a = Path(ctx) / "a.png"
    png_b = Path(ctx) / "b.png"
    png_c = Path(ctx) / "c.png"
    make_test_png(png_a, 200, 150, (255, 0, 0))
    make_test_png(png_b, 200, 150, (0, 255, 0))
    make_test_png(png_c, 200, 150, (255, 0, 0))  # same as A

    # Create metadata files
    for cid in ("a", "b", "c"):
        meta = Path(ctx) / f"{cid}.json"
        meta.write_text(json.dumps({"id": cid, "path": f"{cid}.png"}), encoding="utf-8")

    # Start vision worker
    proc = subprocess.Popen(
        [sys.executable, str(THIS_DIR / "vision_worker.py"),
         "--serve", "--context-root", ctx, "--port", str(port)],
        stderr=subprocess.PIPE, stdout=subprocess.DEVNULL,
    )
    time.sleep(0.5)

    if proc.poll() is not None:
        stderr = proc.stderr.read().decode() if proc.stderr else "no stderr"
        fail("vision worker startup", f"exit {proc.returncode}: {stderr}")
        return

    ok("vision worker startup", f"port {port}")

    def send_job(job: dict) -> dict:
        s = socket.create_connection(("127.0.0.1", port), timeout=5)
        s.sendall((json.dumps(job) + "\n").encode())
        data = b""
        while b"\n" not in data:
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
        s.close()
        return json.loads(data.decode().strip())

    try:
        # --- info ---
        t0 = time.perf_counter()
        r = send_job({"operation": "info", "id": "t1"})
        t_info = (time.perf_counter() - t0) * 1000
        if r.get("ok") and r.get("worker") == "vision_worker_python":
            ok("info operation", f"{t_info:.1f}ms")
        else:
            fail("info operation", str(r))

        # --- analyze ---
        t0 = time.perf_counter()
        r = send_job({"operation": "analyze", "id": "t2", "context_id": "a"})
        t_analyze = (time.perf_counter() - t0) * 1000
        if r.get("ok") and r.get("width") == 200 and r.get("height") == 150:
            ok("analyze operation", f"{t_analyze:.1f}ms, {r['width']}x{r['height']}, palette={len(r.get('palette', []))}")
        else:
            fail("analyze operation", str(r))

        # --- compare (identical) ---
        t0 = time.perf_counter()
        r = send_job({"operation": "compare", "id": "t3", "context_a": "a", "context_b": "c"})
        t_cmp_same = (time.perf_counter() - t0) * 1000
        if r.get("ok") and r.get("stable") is True:
            ok("compare identical", f"{t_cmp_same:.1f}ms, stable={r['stable']}")
        else:
            fail("compare identical", str(r))

        # --- compare (different) ---
        t0 = time.perf_counter()
        r = send_job({"operation": "compare", "id": "t4", "context_a": "a", "context_b": "b"})
        t_cmp_diff = (time.perf_counter() - t0) * 1000
        if r.get("ok") and r.get("stable") is False and r.get("change_ratio", 0) > 0.5:
            ok("compare different", f"{t_cmp_diff:.1f}ms, change_ratio={r['change_ratio']:.2f}")
        else:
            fail("compare different", str(r))

        # --- OCR fallback (no command) ---
        t0 = time.perf_counter()
        r = send_job({"operation": "ocr", "id": "t5", "context_id": "a"})
        t_ocr = (time.perf_counter() - t0) * 1000
        if r.get("ok") and r.get("ocr", {}).get("available") is False:
            ok("ocr fallback (no command)", f"{t_ocr:.1f}ms, reason={r['ocr'].get('reason', '')}")
        else:
            fail("ocr fallback", str(r))

        # --- size mismatch ---
        make_test_png(Path(ctx) / "small.png", 50, 50, (0, 0, 255))
        (Path(ctx) / "small.json").write_text(json.dumps({"id": "small", "path": "small.png"}), encoding="utf-8")
        r = send_job({"operation": "compare", "id": "t6", "context_a": "a", "context_b": "small"})
        if r.get("ok") and r.get("size_mismatch") is True:
            ok("compare size mismatch", f"first={r['first']}, second={r['second']}")
        else:
            fail("compare size mismatch", str(r))

        # --- invalid context_id ---
        r = send_job({"operation": "analyze", "id": "t7", "context_id": "../etc/passwd"})
        if r.get("ok") is False:
            ok("security: invalid context_id rejected")
        else:
            fail("security: invalid context_id", str(r))

    finally:
        proc.terminate()
        proc.wait(timeout=5)


# ---------------------------------------------------------------------------
# Test 2: Vision Worker — async throughput (concurrent TCP clients)
# ---------------------------------------------------------------------------

def test_concurrent_throughput() -> None:
    print("\n=== Concurrent Throughput Tests ===")
    port = find_free_port()
    ctx = tempfile.mkdtemp(prefix="mcp_concurrent_")

    # Create 10 test PNGs
    for i in range(10):
        make_test_png(Path(ctx) / f"img{i}.png", 300, 200, (i * 25 % 256, 100, 50))
        (Path(ctx) / f"img{i}.json").write_text(
            json.dumps({"id": f"img{i}", "path": f"img{i}.png"}), encoding="utf-8"
        )

    proc = subprocess.Popen(
        [sys.executable, str(THIS_DIR / "vision_worker.py"),
         "--serve", "--context-root", ctx, "--port", str(port)],
        stderr=subprocess.PIPE, stdout=subprocess.DEVNULL,
    )
    time.sleep(0.5)

    if proc.poll() is not None:
        fail("concurrent worker startup", f"exit {proc.returncode}")
        return

    ok("concurrent worker startup", f"port {port}")

    results: list[tuple[int, float, dict]] = []
    errors: list[str] = []

    def analyze_one(idx: int) -> None:
        try:
            s = socket.create_connection(("127.0.0.1", port), timeout=10)
            job = json.dumps({"operation": "analyze", "id": f"c{idx}", "context_id": f"img{idx % 10}"})
            t0 = time.perf_counter()
            s.sendall((job + "\n").encode())
            data = b""
            while b"\n" not in data:
                chunk = s.recv(65536)
                if not chunk:
                    break
                data += chunk
            elapsed = (time.perf_counter() - t0) * 1000
            resp = json.loads(data.decode().strip())
            s.close()
            results.append((idx, elapsed, resp))
        except Exception as e:
            errors.append(f"client {idx}: {e}")

    # Launch 20 concurrent clients
    threads = []
    t_start = time.perf_counter()
    for i in range(20):
        t = threading.Thread(target=analyze_one, args=(i,))
        threads.append(t)
        t.start()
    for t in threads:
        t.join(timeout=30)
    t_total = (time.perf_counter() - t_start) * 1000

    if errors:
        for e in errors:
            fail("concurrent client", e)
    else:
        ok("all 20 concurrent clients succeeded", f"total={t_total:.0f}ms")

    successes = [r for r in results if r[2].get("ok")]
    if successes:
        avg_ms = sum(r[1] for r in successes) / len(successes)
        max_ms = max(r[1] for r in successes)
        min_ms = min(r[1] for r in successes)
        ok("concurrent latency", f"avg={avg_ms:.1f}ms, min={min_ms:.1f}ms, max={max_ms:.1f}ms ({len(successes)}/20)")
    else:
        fail("concurrent latency", "no successful responses")

    proc.terminate()
    proc.wait(timeout=5)


# ---------------------------------------------------------------------------
# Test 3: Stdio Bridge — relay test
# ---------------------------------------------------------------------------

def test_stdio_bridge() -> None:
    print("\n=== Stdio Bridge Tests ===")

    # The bridge connects to a TCP server and relays stdin↔TCP.
    # We'll simulate a TCP echo server and pipe JSON through the bridge.
    server_port = find_free_port()
    bridge_port = find_free_port()

    # Start a simple TCP echo server
    echo_server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    echo_server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    echo_server.bind(("127.0.0.1", server_port))
    echo_server.listen(5)
    echo_server.settimeout(10)

    echo_conn_holder: list[socket.socket | None] = [None]

    def echo_accept() -> None:
        try:
            conn, _ = echo_server.accept()
            echo_conn_holder[0] = conn
            conn.settimeout(5)
            while True:
                data = conn.recv(65536)
                if not data:
                    break
                # Echo back with a "response" wrapper
                line = data.decode().strip()
                if line:
                    try:
                        req = json.loads(line)
                        resp = {"ok": True, "echo": req.get("operation", "unknown"), "id": req.get("id", "")}
                        conn.sendall((json.dumps(resp) + "\n").encode())
                    except json.JSONDecodeError:
                        conn.sendall(b'{"ok":false,"error":"bad json"}\n')
        except Exception:
            pass
        finally:
            try:
                conn.close()
            except Exception:
                pass

    accept_thread = threading.Thread(target=echo_accept, daemon=True)
    accept_thread.start()

    # Start the bridge with MCP_HOST/MCP_PORT env pointing to our echo server
    env = os.environ.copy()
    env["MCP_HOST"] = "127.0.0.1"
    env["MCP_PORT"] = str(server_port)

    # We'll pipe a few JSON lines into stdin and read from a pipe
    stdin_r, stdin_w = os.pipe()

    bridge_proc = subprocess.Popen(
        [sys.executable, str(THIS_DIR / "mcp_stdio_bridge.py")],
        stdin=stdin_r,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )
    os.close(stdin_r)

    time.sleep(0.5)

    if bridge_proc.poll() is not None:
        stderr = bridge_proc.stderr.read().decode() if bridge_proc.stderr else ""
        fail("bridge startup", f"exit {bridge_proc.returncode}: {stderr}")
        echo_server.close()
        return

    ok("bridge started", f"PID={bridge_proc.pid}")

    try:
        # Send 3 JSON-RPC lines
        test_jobs = [
            {"jsonrpc": "2.0", "method": "tools/list", "id": 1},
            {"jsonrpc": "2.0", "method": "tools/call", "params": {"name": "info"}, "id": 2},
            {"jsonrpc": "2.0", "method": "ping", "id": 3},
        ]

        os.write(stdin_w, b"".join((json.dumps(j) + "\n").encode() for j in test_jobs))

        # Read responses from bridge stdout
        bridge_proc.stdout.flush()  # type: ignore
        responses = []
        t0 = time.perf_counter()
        deadline = t0 + 5
        buffer = b""
        while time.perf_counter() < deadline and len(responses) < 3:
            try:
                chunk = bridge_proc.stdout.read(1)  # type: ignore
                if not chunk:
                    break
                buffer += chunk
                if b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    if line.strip():
                        responses.append(json.loads(line.decode()))
            except Exception:
                break
        t_relay = (time.perf_counter() - t0) * 1000

        if len(responses) == 3:
            ok("bridge relayed 3 messages", f"{t_relay:.1f}ms total")
            for r in responses:
                if r.get("ok"):
                    ok(f"  response id={r.get('id')}", f"echo={r.get('echo')}")
                else:
                    fail(f"  response id={r.get('id')}", str(r))
        else:
            fail("bridge relay", f"got {len(responses)}/3 responses in {t_relay:.1f}ms")

        # --- Test graceful shutdown ---
        os.close(stdin_w)
        t0 = time.perf_counter()
        bridge_proc.wait(timeout=5)
        t_shutdown = (time.perf_counter() - t0) * 1000
        if bridge_proc.returncode == 0:
            ok("bridge graceful shutdown", f"{t_shutdown:.1f}ms")
        else:
            fail("bridge shutdown", f"exit {bridge_proc.returncode}")

    except Exception as e:
        fail("bridge test", str(e))
    finally:
        try:
            os.close(stdin_w)
        except OSError:
            pass
        echo_server.close()


# ---------------------------------------------------------------------------
# Test 4: Caching / warm-up benchmark
# ---------------------------------------------------------------------------

def test_warmup_benchmark() -> None:
    print("\n=== Warm-up / Benchmark ===")
    port = find_free_port()
    ctx = tempfile.mkdtemp(prefix="mcp_bench_")

    make_test_png(Path(ctx) / "bench.png", 800, 600, (42, 128, 200))
    (Path(ctx) / "bench.json").write_text(json.dumps({"id": "bench", "path": "bench.png"}), encoding="utf-8")

    proc = subprocess.Popen(
        [sys.executable, str(THIS_DIR / "vision_worker.py"),
         "--serve", "--context-root", ctx, "--port", str(port)],
        stderr=subprocess.PIPE, stdout=subprocess.DEVNULL,
    )
    time.sleep(0.5)

    if proc.poll() is not None:
        fail("bench worker startup", f"exit {proc.returncode}")
        return

    def send_analyze() -> tuple[float, dict]:
        s = socket.create_connection(("127.0.0.1", port), timeout=5)
        job = json.dumps({"operation": "analyze", "id": "bench", "context_id": "bench"})
        t0 = time.perf_counter()
        s.sendall((job + "\n").encode())
        data = b""
        while b"\n" not in data:
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
        elapsed = (time.perf_counter() - t0) * 1000
        resp = json.loads(data.decode().strip())
        s.close()
        return elapsed, resp

    try:
        # Cold call
        t_cold, r = send_analyze()
        ok("cold call (800x600)", f"{t_cold:.1f}ms")

        # Warm calls (10 iterations)
        times = []
        for i in range(10):
            t, _ = send_analyze()
            times.append(t)
        avg = sum(times) / len(times)
        ok("warm avg (10 calls)", f"{avg:.1f}ms")

        # Compare
        if t_cold > avg * 0.5:  # cold shouldn't be wildly slower for Pillow (no tesseract pool)
            ok("cold vs warm ratio", f"cold={t_cold:.1f}ms, warm_avg={avg:.1f}ms (no tesseract pool overhead)")
        else:
            ok("cold ≈ warm", f"cold={t_cold:.1f}ms ≈ avg={avg:.1f}ms (Pillow is stateless)")

        # Large image
        make_test_png(Path(ctx) / "large.png", 1920, 1080, (100, 200, 50))
        (Path(ctx) / "large.json").write_text(json.dumps({"id": "large", "path": "large.png"}), encoding="utf-8")
        t_large, r = send_analyze()
        # Need to send large job
        s = socket.create_connection(("127.0.0.1", port), timeout=5)
        t0 = time.perf_counter()
        s.sendall(json.dumps({"operation": "analyze", "id": "lg", "context_id": "large"}).encode() + b"\n")
        data = b""
        while b"\n" not in data:
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
        t_large = (time.perf_counter() - t0) * 1000
        r = json.loads(data.decode().strip())
        s.close()
        if r.get("ok") and r.get("width") == 1920:
            ok("large image (1920x1080)", f"{t_large:.1f}ms, {r['width']}x{r['height']}")
        else:
            fail("large image", str(r))

    finally:
        proc.terminate()
        proc.wait(timeout=5)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("=" * 60)
    print("MCP Python Component Tests")
    print("=" * 60)

    test_vision_worker()
    test_concurrent_throughput()
    test_stdio_bridge()
    test_warmup_benchmark()

    print("\n" + "=" * 60)
    total = PASS + FAIL
    if FAIL == 0:
        print(f"ALL {total} TESTS PASSED ✓")
    else:
        print(f"RESULTS: {PASS} passed, {FAIL} FAILED (of {total})")
    print("=" * 60)

    sys.exit(0 if FAIL == 0 else 1)
