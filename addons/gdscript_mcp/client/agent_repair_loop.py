#!/usr/bin/env python3
"""
Autonomous Repair & Feature Loop Orchestrator for SnipWar MCP.

Executes the closed-loop autonomous lifecycle:
  1. Initialize & Handshake
  2. Baseline Snapshot & Resource Read
  3. Journaled Workspace Sandbox Begin
  4. Import & Atomic Single-Occurrence Patch
  5. Validation & Gated Export with Resource Barrier Settlement
  6. Headless Verification (Preflight / Contract Chains)
  7. Visible Runtime Verification (Freeze/Step & Goal Sequences)
  8. Verdict & Rollback-on-Failure / Archive-on-Success
"""

import argparse
import json
import socket
import sys
import time
from typing import Any, Dict, List, Optional


class McpClientSession:
    def __init__(self, host: str = "127.0.0.1", port: int = 9090, timeout: float = 30.0):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.sock: Optional[socket.socket] = None
        self._req_id = 1

    def connect(self) -> bool:
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.settimeout(self.timeout)
            self.sock.connect((self.host, self.port))
            return True
        except Exception as e:
            print(f"[Client] Connect failed to {self.host}:{self.port}: {e}")
            return False

    def close(self):
        if self.sock:
            try:
                self.sock.close()
            except Exception:
                pass
            self.sock = None

    def send_request(self, method: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        if not self.sock:
            raise RuntimeError("Not connected")
        req_id = self._req_id
        self._req_id += 1
        payload = {"jsonrpc": "2.0", "id": req_id, "method": method}
        if params is not None:
            payload["params"] = params
        data = json.dumps(payload) + "\n"
        self.sock.sendall(data.encode("utf-8"))

        buf = ""
        while "\n" not in buf:
            chunk = self.sock.recv(4096).decode("utf-8")
            if not chunk:
                break
            buf += chunk

        lines = buf.strip().split("\n")
        if not lines:
            return {"error": "Empty response from server"}
        return json.loads(lines[0])

    def call_tool(self, tool_name: str, args: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        resp = self.send_request("tools/call", {"name": tool_name, "arguments": args or {}})
        if "error" in resp:
            return {"ok": False, "error": resp["error"]}
        result = resp.get("result", {})
        content = result.get("content", [])
        if content and content[0].get("type") == "text":
            try:
                return json.loads(content[0].get("text", "{}"))
            except Exception:
                return {"_raw": content[0].get("text")}
        return result

    def read_resource(self, uri: str) -> Dict[str, Any]:
        resp = self.send_request("resources/read", {"uri": uri})
        if "error" in resp:
            return {"ok": False, "error": resp["error"]}
        result = resp.get("result", {})
        contents = result.get("contents", [])
        if contents and "text" in contents[0]:
            try:
                return json.loads(contents[0]["text"])
            except Exception:
                return {"_raw": contents[0]["text"]}
        return result


class AutonomousRepairOrchestrator:
    def __init__(self, client: McpClientSession):
        self.client = client
        self.session_id = ""

    def run_repair_cycle(
        self,
        goal_intent: str,
        target_file: str,
        old_text: str,
        new_text: str,
        chain_steps: Optional[List[Dict[str, Any]]] = None,
        goal_sequence: Optional[List[Dict[str, Any]]] = None,
    ) -> Dict[str, Any]:
        print(f"\n=======================================================")
        print(f" [AUTONOMY] Starting Autonomous Repair Cycle")
        print(f" Goal: {goal_intent}")
        print(f" Target: {target_file}")
        print(f"=======================================================\n")

        # 1. Initialize Handshake
        print("[1/8] Performing Protocol Handshake...")
        init_res = self.client.send_request("initialize", {"protocolVersion": "2026-07-28"})
        self.client.send_request("initialized", {})
        print(f"      Connected. Protocol: {init_res.get('result', {}).get('protocolVersion')}")

        # 2. Baseline Status via MCP Resources
        print("[2/8] Fetching System Baseline Snapshot via MCP Resources...")
        state_summary = self.client.read_resource("godot://gameState/summary")
        print(f"      Baseline Faction Status: {state_summary.get('faction', 'a')} | Homeworld: {state_summary.get('homeworld', '?')}")

        # 3. Workspace Begin
        print("[3/8] Opening Isolated Workspace Sandbox...")
        ws_begin = self.client.call_tool("runtime_autonomy_workspace_begin", {"project_id": "snipwar"})
        if not ws_begin.get("ok", False):
            print(f"      [BLOCKED] Workspace Begin Failed: {ws_begin}")
            return {"verdict": "BLOCKED", "error": ws_begin}
        self.session_id = ws_begin.get("workspace", {}).get("session_id", "")
        print(f"      Workspace Active: {ws_begin.get('workspace', {}).get('run_id')}")

        # 4. Import & Single-Occurrence Patch
        print(f"[4/8] Importing {target_file} and Applying Patch...")
        imp_res = self.client.call_tool("runtime_autonomy_workspace_import", {"path": target_file})
        if not imp_res.get("ok", False):
            print(f"      [FAIL] Import Failed: {imp_res}")
            return self._rollback_and_fail("Import failed", imp_res)

        patch_res = self.client.call_tool("runtime_autonomy_patch", {
            "path": imp_res.get("workspace_path", ""),
            "old_text": old_text,
            "new_text": new_text,
        })
        if not patch_res.get("ok", False):
            print(f"      [FAIL] Patch Failed: {patch_res}")
            return self._rollback_and_fail("Patch failed", patch_res)
        print(f"      Patch Applied (Tx: {patch_res.get('transaction_id')})")

        # 5. Gated Export with Resource Barrier
        print("[5/8] Validating Diagnostics and Exporting with Resource Barrier...")
        export_res = self.client.call_tool("runtime_autonomy_export", {"path": target_file, "apply": True})
        if not export_res.get("ok", False):
            print(f"      [FAIL] Export Validation / Barrier Failed: {export_res}")
            return self._rollback_and_fail("Export validation failed", export_res)
        print(f"      Export Succeeded. Resource Barrier Settled in {export_res.get('resource_barrier', {}).get('duration_ms', 0)} ms")

        # 6. Headless Verification (Chain Runner)
        if chain_steps:
            print("[6/8] Executing Declarative Verification Chain...")
            chain_res = self.client.call_tool("runtime_chain_run", {
                "name": f"verify_{goal_intent}",
                "steps": chain_steps,
            })
            if chain_res.get("verdict") != "PASS":
                print(f"      [FAIL] Chain Verification Failed: {chain_res.get('failure_reason')}")
                return self._rollback_and_fail("Verification Chain Failed", chain_res)
            print(f"      Chain PASSED ({chain_res.get('completed_steps')} steps)")
        else:
            print("[6/8] Skipping Declarative Chain (no steps provided).")

        # 7. Visible Runtime Verification (Goal Sequence)
        if goal_sequence:
            print("[7/8] Executing Visible Gameplay Sequence...")
            seq_res = self.client.call_tool("runtime_goal_sequence", {"actions": goal_sequence})
            if seq_res.get("verdict") != "PASS":
                print(f"      [FAIL] Visible Goal Sequence Failed: {seq_res.get('reason')}")
                return self._rollback_and_fail("Goal Sequence Failed", seq_res)
            print(f"      Visible Sequence PASSED.")
        else:
            print("[7/8] Skipping Visible Goal Sequence.")

        # 8. Success Conclude
        print("[8/8] Finalizing Run Workspace & Archiving Trace...")
        self.client.call_tool("runtime_autonomy_workspace_end", {})
        print("\n>>> AUTONOMOUS REPAIR CYCLE: VERDICT = PASS <<<\n")
        return {
            "verdict": "PASS",
            "goal": goal_intent,
            "target": target_file,
            "session_id": self.session_id,
        }

    def _rollback_and_fail(self, reason: str, details: Any) -> Dict[str, Any]:
        print(f"\n[AUTONOMY] Triggering Automatic Rollback due to failure: {reason}")
        rb = self.client.call_tool("runtime_autonomy_rollback_all", {})
        self.client.call_tool("runtime_autonomy_workspace_end", {})
        print(f"           Rollback Result: {rb.get('ok', False)}")
        return {
            "verdict": "FAIL",
            "reason": reason,
            "details": details,
            "rolled_back": rb.get("ok", False),
        }


def main():
    parser = argparse.ArgumentParser(description="Autonomous Repair Loop Orchestrator")
    parser.add_argument("--port", type=int, default=9090, help="MCP Server TCP Port")
    parser.add_argument("--host", type=str, default="127.0.0.1", help="MCP Server Host")
    parser.add_argument("--file", type=str, default="", help="Target file path (res://...)")
    parser.add_argument("--old", type=str, default="", help="Old text to replace")
    parser.add_argument("--new", type=str, default="", help="New replacement text")
    parser.add_argument("--goal", type=str, default="smoke_test", help="Goal description")
    args = parser.parse_args()

    client = McpClientSession(host=args.host, port=args.port)
    if not client.connect():
        sys.exit(1)

    orchestrator = AutonomousRepairOrchestrator(client)
    if args.file and args.old and args.new:
        res = orchestrator.run_repair_cycle(
            goal_intent=args.goal,
            target_file=args.file,
            old_text=args.old,
            new_text=args.new,
        )
        client.close()
        sys.exit(0 if res.get("verdict") == "PASS" else 1)
    else:
        print("[Client] Orchestrator ready. Pass --file, --old, and --new to execute an automated cycle.")
        client.close()


if __name__ == "__main__":
    main()
