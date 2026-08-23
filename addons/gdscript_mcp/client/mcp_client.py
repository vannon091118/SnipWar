#!/usr/bin/env python3
"""
Artifact-first MCP client for Godot.

The client receives compact screenshot metadata from the runtime session. Image
bytes stay in the session-local context directory and are analyzed by the
supervised local worker through MCP tool calls.

Usage:
    node is not required; this client uses only the Python standard library.
    python mcp_client.py --port 9090 --one-shot
    python mcp_client.py --port 9090 --click "Neues Spiel"
"""

from __future__ import annotations

import argparse
import json
import socket
import sys
import time
from typing import Any


class McpClient:
    def __init__(self, host: str = "127.0.0.1", port: int = 9090, timeout: float = 15.0):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.sock: socket.socket | None = None
        self._id = 0
        self._receive_buffer = b""

    def connect(self) -> None:
        self.sock = socket.create_connection((self.host, self.port), timeout=self.timeout)
        self._call("initialize", {"protocolVersion": "2024-11-05"})
        self._call("initialized", {})

    def close(self) -> None:
        if self.sock is not None:
            self.sock.close()
            self.sock = None

    def _call(self, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        if self.sock is None:
            raise ConnectionError("MCP client is not connected")
        self._id += 1
        message = {
            "jsonrpc": "2.0",
            "id": self._id,
            "method": method,
            "params": params or {},
        }
        self.sock.sendall((json.dumps(message, separators=(",", ":")) + "\n").encode("utf-8"))
        deadline = time.monotonic() + self.timeout
        while b"\n" not in self._receive_buffer:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f"MCP request timed out: {method}")
            self.sock.settimeout(remaining)
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("MCP server closed the connection")
            self._receive_buffer += chunk
        line, self._receive_buffer = self._receive_buffer.split(b"\n", 1)
        return json.loads(line.decode("utf-8"))

    def tool(self, name: str, arguments: dict[str, Any] | None = None) -> dict[str, Any]:
        response = self._call("tools/call", {"name": name, "arguments": arguments or {}})
        if "error" in response:
            return {"error": response["error"], "tool": name}
        result = response.get("result", {})
        if result.get("isError"):
            return {"error": result, "tool": name}
        merged: dict[str, Any] = {}
        for content in result.get("content", []):
            if content.get("type") != "text":
                continue
            text = content.get("text", "")
            try:
                value = json.loads(text)
            except json.JSONDecodeError:
                merged["raw"] = text
                continue
            if isinstance(value, dict):
                merged.update(value)
            else:
                merged["value"] = value
        return merged

    def screenshot(self, persist_context: bool = True) -> dict[str, Any]:
        return self.tool("runtime_screenshot", {"format": "png", "persist_context": persist_context})

    def analyze(self) -> dict[str, Any]:
        """Capture a local artifact, then request bounded worker analysis."""
        screenshot = self.screenshot(True)
        if "error" in screenshot:
            return screenshot
        context_id = str(screenshot.get("context_id", ""))
        result: dict[str, Any] = {
            "artifact": screenshot,
            "context_id": context_id,
            "local_path": screenshot.get("context", {}).get("absolute_path", ""),
        }
        if context_id:
            result["worker"] = self.tool(
                "runtime_vision_worker_analyze",
                {"context_id": context_id, "ocr": False},
            )
        result["live"] = self.tool("runtime_ux_scan", {})
        return result

    def click(self, x: int, y: int) -> dict[str, Any]:
        return self.tool("runtime_click", {"x": x, "y": y})

    def click_button(self, description: str) -> dict[str, Any]:
        return self.tool("runtime_ux_click", {"description": description})

    def status(self) -> dict[str, Any]:
        return self.tool("runtime_mcp_status", {})

    def release(self, context_id: str) -> dict[str, Any]:
        return self.tool("runtime_context_release", {"context_id": context_id})


def print_json(value: Any) -> None:
    print(json.dumps(value, indent=2, ensure_ascii=False, default=str))


def main() -> int:
    parser = argparse.ArgumentParser(description="Artifact-first MCP client for Godot")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9090)
    parser.add_argument("--auto", action="store_true", help="Analyze every two seconds")
    parser.add_argument("--one-shot", action="store_true", help="Analyze once and exit")
    parser.add_argument("--click", help="Run runtime_ux_click for a visible description")
    args = parser.parse_args()

    client = McpClient(args.host, args.port)
    try:
        print(f"Connecting to {args.host}:{args.port}...")
        client.connect()
        print("Connected.")
        if args.click:
            print_json(client.click_button(args.click))
            return 0
        if args.auto:
            while True:
                started = time.monotonic()
                print_json({"elapsed_ms": round((time.monotonic() - started) * 1000.0, 1), **client.analyze()})
                time.sleep(2.0)
        print_json(client.analyze())
        return 0
    except KeyboardInterrupt:
        return 0
    except Exception as error:
        print(f"MCP client error: {error}", file=sys.stderr)
        return 1
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
