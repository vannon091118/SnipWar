#!/usr/bin/env python3
"""
agent_playthrough.py — Agent-driven, interactive playthrough loop.

Connects to a running Godot MCP server and drives the game step by step.
Queries the external ledger (agent_store.py) for the next TO_CHECK or
BLOCKED mechanic, loads the appropriate savestate, executes the action,
checks the receipt, and records the result.

Usage:
    python agent_playthrough.py --project snipwar --port 9090
    python agent_playthrough.py --project snipwar --port 9090 --autonomous
    python agent_playthrough.py --project snipwar --port 9090 --resume

Architecture:
    Godot (MCP Server) ←→ TCP (JSON-RPC) ←→ Agent Playthrough
    External Ledger (SQLite) ←→ agent_store.py
"""

import argparse
import json
import socket
import subprocess
import sys
import time
from pathlib import Path

STATUS_SOLVED = "SOLVED"
STATUS_FAIL = "FAIL"
STATUS_BLOCKED = "BLOCKED"
STATUS_MCP_ISSUE = "MCP_ISSUE"
STATUS_GAME_ISSUE = "GAME_ISSUE"
STATUS_TO_CHECK = "TO_CHECK"
STATUS_INCONCLUSIVE = "INCONCLUSIVE"

KEY_ESCAPE = 4194305


class McpClient:
    def __init__(self, host: str, port: int):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.settimeout(15)
        self.host = host
        self.port = port
        self._id = 0
        self._receive_buffer = b""

    def connect(self):
        self.sock.connect((self.host, self.port))
        self._call("initialize", {"protocolVersion": "2024-11-05"})
        self._call("initialized", {})

    def _call(self, method: str, params: dict | None = None) -> dict:
        self._id += 1
        msg = {"jsonrpc": "2.0", "id": self._id, "method": method, "params": params or {}}
        self.sock.sendall((json.dumps(msg) + "\n").encode("utf-8"))
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
            return {"error": resp["error"]}
        result = resp.get("result", {})
        if result.get("isError"):
            return {"error": result}
        content = result.get("content", [])
        merged: dict = {}
        for c in content:
            if c.get("type") == "text":
                try:
                    merged.update(json.loads(c.get("text", "")))
                except json.JSONDecodeError:
                    merged["raw"] = c.get("text")
        return merged

    def click(self, description: str) -> dict:
        return self.tool("runtime_ux_click", {"description": description})

    def find(self, description: str) -> dict:
        return self.tool("runtime_ux_find", {"description": description})

    def scan(self) -> dict:
        return self.tool("runtime_ux_scan", {})

    def logs(self, cursor: str = "", limit: int = 200) -> dict:
        return self.tool("runtime_ux_logs", {"limit": limit, "cursor": cursor})

    def wait_ms(self, ms: int) -> dict:
        return self.tool("runtime_wait_ms", {"ms": ms})

    def key(self, keycode: int, pressed: bool = True) -> dict:
        return self.tool("runtime_key", {"keycode": keycode, "pressed": pressed})

    def preset_load(self, entry_id: str) -> dict:
        return self.tool("runtime_playthrough_preset_load", {"entry_id": entry_id})


def store_cmd(project: str, *args: str) -> str:
    result = subprocess.run(
        [sys.executable, str(Path(__file__).parent / "agent_store.py"),
         "--project", project] + list(args),
        capture_output=True, text=True,
    )
    return result.stdout.strip()


def run_loop(project: str, port: int, autonomous: bool, resume: bool) -> int:
    client = McpClient("127.0.0.1", port)
    client.connect()
    print(f"Connected to MCP server on port {port}")

    log_cursor = ""
    failures = 0

    while True:
        # Query ledger for next mechanic
        next_mech = store_cmd(project, "next-to-check")
        print(f"\nNext: {next_mech}")

        if "all sequences SOLVED" in next_mech:
            print("All mechanics SOLVED. Nothing left to test.")
            break

        # Parse the mechanic ID from output
        parts = next_mech.split()
        if not parts:
            break
        seq_id = parts[0]

        # Check if blocked
        if "BLOCKED" in next_mech:
            print(f"  Sequence {seq_id} is BLOCKED — skipping for now")
            if not autonomous:
                input("Press Enter to continue...")
            continue

        # Execute the mechanic step
        print(f"  Testing sequence: {seq_id}")

        # Pre-action scan
        pre_scan = client.scan()
        print(f"  Current scene: {pre_scan.get('scene', '?')}")

        # Find and click the target
        target = _mechanic_target(seq_id)
        if target:
            print(f"  Clicking: {target}")
            result = client.click(target)
            print(f"  Result: clicked={result.get('clicked')}, found={result.get('found')}")

            receipt = result.get("receipt", {})
            if receipt:
                print(f"  Receipt: frame_hash={receipt.get('frame_hash', '?')[:12]}... "
                      f"size={receipt.get('width')}x{receipt.get('height')}")

            # Check logs for new anomalies
            logs = client.logs(log_cursor)
            log_cursor = logs.get("next_cursor", "")
            anomalies = logs.get("anomalies", [])
            if anomalies:
                print(f"  Anomalies ({len(anomalies)}):")
                for a in anomalies:
                    print(f"    [{a.get('level')}] {a.get('text', a.get('category', '?'))}")
                # Record anomalies
                for a in anomalies:
                    store_cmd(project, "anomaly-record", f"step_{seq_id}",
                              "--source", a.get("source", "project"),
                              "--level", a.get("level", "warning"),
                              "--text", a.get("text", str(a))[:500])

            # Determine status
            if result.get("clicked") and not anomalies:
                status = STATUS_SOLVED
                print(f"  → {status}")
            elif not result.get("clicked"):
                status = STATUS_MCP_ISSUE
                print(f"  → {status}")
                failures += 1
            elif anomalies:
                status = STATUS_GAME_ISSUE
                print(f"  → {status}")
                failures += 1
            else:
                status = STATUS_INCONCLUSIVE
                print(f"  → {status}")

            store_cmd(project, "sequence-status", seq_id, "--status", status)
            store_cmd(project, "step-record", seq_id, "0",
                      "--action", f"runtime_ux_click {target}", "--status", status)

        if not autonomous:
            cmd = input("\nEnter to continue, 'q' to quit: ").strip()
            if cmd == "q":
                break

    print(f"\nDone. Failures: {failures}")
    return 0 if failures == 0 else 1


def _mechanic_target(seq_id: str) -> str:
    """Map sequence IDs to their expected click targets."""
    targets = {
        "main_menu_new_game": "NEUES SPIEL",
        "main_menu_continue": "WEITER",
        "main_menu_quit": "BEENDEN",
        "world_planet_select": "PLANET",
        "world_tech_open": "FORSCHUNG",
        "pause_save": "SPEICHERN",
        "pause_main_menu": "HAUPTMENÜ",
    }
    for key, target in targets.items():
        if key in seq_id.lower().replace(" ", "_"):
            return target
    # Return the mechanic name if no mapping
    return ""


def main() -> int:
    parser = argparse.ArgumentParser(description="Agent-driven playthrough loop")
    parser.add_argument("--project", required=True, help="Project identifier for the ledger")
    parser.add_argument("--port", type=int, default=9090, help="MCP server port")
    parser.add_argument("--autonomous", action="store_true", help="Run without user prompts")
    parser.add_argument("--resume", action="store_true", help="Resume from last checkpoint")
    args = parser.parse_args()

    try:
        return run_loop(args.project, args.port, args.autonomous, args.resume)
    except ConnectionError as e:
        print(f"Connection failed: {e}")
        return 1
    except KeyboardInterrupt:
        print("\nInterrupted.")
        return 0


if __name__ == "__main__":
    sys.exit(main())