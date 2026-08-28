#!/usr/bin/env python3
"""Stdio↔TCP bridge: exposes the SnipWar MCP runtime (default 127.0.0.1:9090)
as a local stdio connector so any MCP client can register it.

One JSON-RPC message per line, bidirectional passthrough, stdlib-only (no pip).
Diagnostics go to stderr ONLY — stdout carries protocol traffic exclusively.

Requires a VISIBLE running game:
    $GODOT_BIN --path . -- --mcp --mcp-port 9090

Stability:
  * Repeated connect attempts (server starts asynchronously — initial connect
    may fail while the editor is still booting).
  * Write-buffering for stdin input until TCP is open (otherwise the client's
    first calls are lost before the server is listening).
  * Graceful shutdown with 1.5 s reply-flush so the last request's answer
    still reaches the client when stdin closes right after the final call.
"""
from __future__ import annotations

import os
import select
import socket
import sys
import time

# ---------------------------------------------------------------------------
# Configuration (env-overridable)
# ---------------------------------------------------------------------------
HOST: str = os.environ.get("MCP_HOST", "127.0.0.1")
PORT: int = int(os.environ.get("MCP_PORT", "9090"))
CONNECT_RETRY_MS: int = 750
CONNECT_RETRY_MAX: int = 40  # ~30 s, then hard exit


def _stderr(msg: str) -> None:
    """All diagnostics to stderr, never to stdout."""
    sys.stderr.write(msg + "\n")
    sys.stderr.flush()


def main() -> None:
    sock: socket.socket | None = None
    connect_attempts: int = 0
    pending_writes: list[str] = []
    sbuf: str = ""
    last_retry: float = 0.0
    stdin_bin = sys.stdin.buffer

    def try_connect() -> socket.socket | None:
        nonlocal sock, connect_attempts
        if sock is not None:
            return sock
        try:
            s = socket.create_connection((HOST, PORT), timeout=2)
            s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except OSError:
            connect_attempts += 1
            if connect_attempts >= CONNECT_RETRY_MAX:
                _stderr(
                    f"[snipwar-mcp-bridge] tcp error: ECONNREFUSED — "
                    f"start the game first: $GODOT_BIN --path . -- --mcp --mcp-port {PORT}"
                )
                sys.exit(1)
            return None
        # Success — flush buffered stdin lines
        sock = s
        connect_attempts = 0
        for line in pending_writes:
            try:
                s.sendall((line + "\n").encode("utf-8"))
            except OSError:
                break
        pending_writes.clear()
        _stderr("[snipwar-mcp-bridge] connected")
        return s

    # Initial connect
    try_connect()

    while True:
        # --- Build select-list ---
        rlist: list = [stdin_bin]
        if sock is not None:
            rlist.append(sock)

        try:
            readable, _, _ = select.select(rlist, [], [], 0.01)
        except (ValueError, OSError):
            break

        # --- TCP → stdout ---
        if sock is not None and sock in readable:
            try:
                data = sock.recv(65536)
            except OSError:
                data = b""
            if not data:
                # Server dropped
                sock.close()
                sock = None
                connect_attempts = 0
                last_retry = time.monotonic()
            else:
                sbuf += data.decode("utf-8", errors="replace")
                while "\n" in sbuf:
                    line, sbuf = sbuf.split("\n", 1)
                    line = line.strip()
                    if line:
                        sys.stdout.write(line + "\n")
                        sys.stdout.flush()

        # --- stdin → TCP ---
        if stdin_bin in readable:
            try:
                raw = stdin_bin.readline()
            except Exception:
                raw = b""
            if not raw:
                # stdin closed — graceful shutdown
                time.sleep(1.5)
                # Final TCP drain
                if sock is not None:
                    try:
                        data = sock.recv(65536)
                        if data:
                            sbuf += data.decode("utf-8", errors="replace")
                            while "\n" in sbuf:
                                line, sbuf = sbuf.split("\n", 1)
                                line = line.strip()
                                if line:
                                    sys.stdout.write(line + "\n")
                                    sys.stdout.flush()
                    except OSError:
                        pass
                break
            line = raw.decode("utf-8", errors="replace").strip()
            if not line:
                continue
            if sock is not None:
                try:
                    sock.sendall((line + "\n").encode("utf-8"))
                except OSError:
                    pending_writes.append(line)
            else:
                pending_writes.append(line)

        # --- Reconnect retry ---
        if sock is None:
            now = time.monotonic()
            if now - last_retry >= CONNECT_RETRY_MS / 1000.0:
                last_retry = now
                try_connect()

    sys.exit(0)


if __name__ == "__main__":
    main()
