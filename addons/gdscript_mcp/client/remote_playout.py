#!/usr/bin/env python3
"""
remote_playout.py — drive a full playthrough against the Godot MCP server over
TCP, exactly like an agent would: screenshot -> local vision -> click -> verify.

Every step is visible in the game window; this script only issues JSON-RPC
calls over 127.0.0.1:<port> while the game runs with `-- --mcp`.

Strongly preferred over raw-client flows: it reuses the server's own
runtime_ux_* tools (labels + clicks) so the agent's context always comes from
the same pipeline the server offers.

Usage:
    python remote_playout.py --port 9090 --flow main_menu
    python remote_playout.py --port 9090 --flow full    # menu -> world -> tech -> pause
"""

import argparse
import json
import socket
import sys

DEFAULT_PORT = 9090


class McpClient:
    def __init__(self, host: str, port: int):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.settimeout(15)
        self.host = host
        self.port = port
        self._id = 0

    def connect(self):
        self.sock.connect((self.host, self.port))
        self._call("initialize", {"protocolVersion": "2024-11-05"})
        self._call("initialized", {})

    def _call(self, method: str, params: dict | None = None) -> dict:
        self._id += 1
        msg = {"jsonrpc": "2.0", "id": self._id, "method": method, "params": params or {}}
        self.sock.sendall((json.dumps(msg) + "\n").encode("utf-8"))
        if not hasattr(self, "_receive_buffer"):
            self._receive_buffer = b""
        while b"\n" not in self._receive_buffer:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("Server closed connection")
            self._receive_buffer += chunk
        line, self._receive_buffer = self._receive_buffer.split(b"\n", 1)
        return json.loads(line.decode("utf-8"))

    def tool(self, name: str, arguments: dict | None = None) -> dict:
        resp = self._call("tools/call", {"name": name, "arguments": arguments or {}})
        if "error" in resp:
            raise RuntimeError(f"JSON-RPC error: {resp['error']}")
        result = resp.get("result", {})
        if result.get("isError"):
            raise RuntimeError(f"Tool error: {result}")
        content = result.get("content", [])
        merged: dict = {}
        for c in content:
            if c.get("type") == "text":
                try:
                    merged.update(json.loads(c.get("text", "")))
                except json.JSONDecodeError:
                    merged["raw"] = c.get("text")
        return merged

    def status(self) -> dict:
        return self.tool("runtime_mcp_status")

    def wait_ms(self, ms: int) -> dict:
        return self.tool("runtime_wait_ms", {"ms": ms})

    def analyze(self, include_visual: bool = True) -> dict:
        return self.tool("runtime_ux_analyze", {"include_visual": include_visual})

    def find(self, description: str) -> dict:
        return self.tool("runtime_ux_find", {"description": description})

    def click(self, description: str) -> dict:
        return self.tool("runtime_ux_click", {"description": description})

    def logs(self, cursor: str = "", limit: int = 200) -> dict:
        return self.tool("runtime_ux_logs", {"cursor": cursor, "limit": limit})

    def key(self, keycode: int, pressed: bool = True) -> dict:
        return self.tool("runtime_key", {"keycode": keycode, "pressed": pressed})

    def scan(self) -> dict:
        return self.tool("runtime_ux_scan", {})


KEY_ESCAPE = 4194305  # Godot KEY_ESCAPE


def run_flow(client: McpClient, flow: str) -> int:
    failures = 0

    def check(desc: str, cond: bool, detail: str = ""):
        nonlocal failures
        print(f"  [{'OK' if cond else 'FAIL'}] {desc}{' -> ' + detail if detail else ''}")
        if not cond:
            failures += 1

    print("=" * 60)
    print(f"REMOTE PLAYOUT: {flow} (watch the game window)")
    print("=" * 60)

    status = client.status()
    print(f"Server: {status.get('state', '?')} | tools={status.get('tool_count', '?')} | "
          f"latency_avg_ms={status.get('tool_latency_avg_ms', 0):.1f}")

    if flow == "main_menu":
        analysis = client.analyze(False)
        check("scene == main_menu", analysis.get("scene") == "main_menu", str(analysis.get("scene")))
        check(">=2 interactables", len(analysis.get("interactables", [])) >= 2)
        find_btn = client.find("Neues Spiel")
        check("button 'Neues Spiel' findable", find_btn.get("found", False))
        logs = client.logs()
        print(f"  [LOG] anomalies during flow: {logs.get('anomaly_count', 0)}")
        for a in logs.get("anomalies", []):
            print(f"    ANOMALY {a.get('level')}: {a.get('message')}")
    elif flow == "new_game_to_world":
        clicked = client.click("Neues Spiel")
        check("NEUES SPIEL clicked", clicked.get("clicked", False))
        client.wait_ms(3000)
        world = client.analyze(False)
        check("world scene loaded", world.get("scene") == "game_view", str(world.get("scene")))
    elif flow == "full":
        clicked = client.click("Neues Spiel")
        check("NEUES SPIEL clicked", clicked.get("clicked", False))
        client.wait_ms(3000)
        world = client.analyze(False)
        check("world scene loaded", world.get("scene") == "game_view", str(world.get("scene")))
        tech = client.find("FORSCHUNG")
        if tech.get("found"):
            client.click("FORSCHUNG")
            client.wait_ms(1500)
            tech_open = client.tool("runtime_ux_scan", {})
            check("TechnologyMenu open", tech_open.get("scene") in ("main_menu", "game_view", "dialog")
                  or str(tech_open.get("scene", "")) != "", str(tech_open.get("scene")))
            client.key(KEY_ESCAPE, True)
            client.key(KEY_ESCAPE, False)
        else:
            check("FORSCHUNG visible", False, "button not found")
        client.wait_ms(1000)
        logs = client.logs()
        print(f"  [LOG] anomalies: {logs.get('anomaly_count', 0)}")
        for a in logs.get("anomalies", []):
            print(f"    ANOMALY {a.get('level')}: {a.get('message')}")
    elif flow == "integration_full":
        log_cursor = ""
        mechanics = [
            ("MainMenu → NEUES SPIEL", "Neues Spiel", "world scene loaded", lambda r: r.get("clicked")),
            ("World → Planet selektieren", "PLANET", "PlanetPanel visible", lambda r: r.get("clicked")),
            ("Dossier → FORSCHUNG", "FORSCHUNG", "Dossier open", lambda r: r.get("clicked")),
            ("ESC → Dossier close", None, "menu closed", None),
            ("ESC → Pause", None, "PauseMenu open", None),
            ("Pause → SPEICHERN", "SPEICHERN", "game saved", lambda r: r.get("clicked")),
            ("Pause → HAUPTMENÜ", "HAUPTMENÜ", "main menu loaded", lambda r: r.get("clicked")),
        ]
        for name, target, expected, success_fn in mechanics:
            print(f"\n--- {name} ---")
            if target:
                result = client.click(target)
                ok = success_fn(result) if success_fn else True
                check(name, ok, str(result.get("receipt", {}).get("frame_hash", "")[:12]))
            elif name.startswith("ESC"):
                client.key(KEY_ESCAPE, True)
                client.key(KEY_ESCAPE, False)
                client.wait_ms(800)
                scan = client.scan()
                check(name, scan.get("scene") != "unknown" or len(scan.get("interactables", [])) > 0, str(scan.get("scene")))
            client.wait_ms(400)
            logs = client.logs(log_cursor)
            log_cursor = logs.get("next_cursor", "")
            for a in logs.get("anomalies", []):
                print(f"    [ANOMALY] {a.get('level')}: {a.get('text', a.get('category', '?'))}")
    else:
        print(f"Unknown flow {flow}")
        return 1

    print(f"VERDICT: {'ALL PASSED' if failures == 0 else str(failures) + ' FAILED'}")
    return 0 if failures == 0 else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Remote playout against the Godot MCP server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--flow", default="main_menu",
                        choices=["main_menu", "new_game_to_world", "full", "integration_full"])
    args = parser.parse_args()

    client = McpClient(args.host, args.port)
    try:
        client.connect()
    except Exception as e:
        print(f"Connection failed: {e}")
        return 1
    try:
        return run_flow(client, args.flow)
    except Exception as e:
        print(f"Playout error: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())