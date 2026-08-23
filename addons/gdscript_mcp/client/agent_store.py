#!/usr/bin/env python3
"""
agent_store.py — External ledger for MCP playthrough results.

Stores sequences, steps, screenshots, checkpoints, and anomalies in a
project-specific SQLite database. The agent queries this ledger to decide
the next action instead of following a linear script.

Database location: {MCP_AGENT_STORE}/projects/{project_hash}/ledger.db
Override via AGENT_STORE_ROOT environment variable (default: ./agent_store).

Usage:
    python agent_store.py --project snipwar sequence-list
    python agent_store.py --project snipwar sequence-new "main_menu_new_game"
    python agent_store.py --project snipwar step-record seq_1 0 \
        --action "runtime_ux_click" --status SOLVED
    python agent_store.py --project snipwar screenshot-link step_1 \
        --path "frames/frame_42.png" --hash "abc123" --kind milestone
"""

import argparse
import hashlib
import json
import os
import sqlite3
import sys
import time
from pathlib import Path

DEFAULT_STORE_ROOT = os.environ.get("AGENT_STORE_ROOT", "agent_store")

STATUS_VALUES = ("TO_CHECK", "SOLVED", "FAIL", "BLOCKED", "MCP_ISSUE", "GAME_ISSUE", "INCONCLUSIVE")
SCREENSHOT_KINDS = ("milestone", "failure", "checkpoint", "reference")


def project_hash(project_id: str) -> str:
    return hashlib.sha256(project_id.encode()).hexdigest()[:16]


def db_path(project_id: str, store_root: str = DEFAULT_STORE_ROOT) -> Path:
    return Path(store_root) / "projects" / project_hash(project_id) / "ledger.db"


def get_conn(project_id: str, store_root: str = DEFAULT_STORE_ROOT) -> sqlite3.Connection:
    p = db_path(project_id, store_root)
    p.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(p))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    _init_schema(conn)
    return conn


def _init_schema(conn: sqlite3.Connection) -> None:
    conn.executescript("""
    CREATE TABLE IF NOT EXISTS runs (
        id TEXT PRIMARY KEY,
        project_hash TEXT NOT NULL,
        started_at REAL NOT NULL,
        ended_at REAL,
        notes TEXT DEFAULT ''
    );

    CREATE TABLE IF NOT EXISTS sequences (
        id TEXT PRIMARY KEY,
        run_id TEXT REFERENCES runs(id),
        mechanic TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'TO_CHECK',
        solved_count INTEGER NOT NULL DEFAULT 0,
        fail_count INTEGER NOT NULL DEFAULT 0,
        blocked_reason TEXT DEFAULT '',
        last_tested_at REAL,
        created_at REAL NOT NULL DEFAULT (strftime('%s','now'))
    );

    CREATE TABLE IF NOT EXISTS steps (
        id TEXT PRIMARY KEY,
        sequence_id TEXT NOT NULL REFERENCES sequences(id),
        step_index INTEGER NOT NULL DEFAULT 0,
        action TEXT NOT NULL DEFAULT '',
        action_args TEXT NOT NULL DEFAULT '{}',
        expected_live TEXT DEFAULT '',
        expected_visual TEXT DEFAULT '',
        actual_live TEXT DEFAULT '',
        actual_visual TEXT DEFAULT '',
        log_delta TEXT DEFAULT '',
        status TEXT NOT NULL DEFAULT 'TO_CHECK',
        ts REAL NOT NULL DEFAULT (strftime('%s','now'))
    );

    CREATE TABLE IF NOT EXISTS screenshots (
        id TEXT PRIMARY KEY,
        step_id TEXT REFERENCES steps(id),
        path TEXT NOT NULL DEFAULT '',
        hash TEXT NOT NULL DEFAULT '',
        kind TEXT NOT NULL DEFAULT 'milestone',
        width INTEGER DEFAULT 0,
        height INTEGER DEFAULT 0,
        ts REAL NOT NULL DEFAULT (strftime('%s','now'))
    );

    CREATE TABLE IF NOT EXISTS checkpoints (
        id TEXT PRIMARY KEY,
        run_id TEXT REFERENCES runs(id),
        sequence_id TEXT REFERENCES sequences(id),
        step_index INTEGER NOT NULL DEFAULT 0,
        preset_path TEXT NOT NULL DEFAULT '',
        screenshot_ref TEXT DEFAULT '',
        ts REAL NOT NULL DEFAULT (strftime('%s','now'))
    );

    CREATE TABLE IF NOT EXISTS anomalies (
        id TEXT PRIMARY KEY,
        step_id TEXT REFERENCES steps(id),
        source TEXT NOT NULL DEFAULT '',
        level TEXT NOT NULL DEFAULT 'info',
        category TEXT NOT NULL DEFAULT '',
        text TEXT NOT NULL DEFAULT '',
        stamp TEXT NOT NULL DEFAULT ''
    );
    """)


def _uid() -> str:
    return f"{int(time.time() * 1000)}_{os.urandom(4).hex()}"


def cmd_sequence_list(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    rows = conn.execute(
        "SELECT id, mechanic, description, status, solved_count, fail_count "
        "FROM sequences ORDER BY created_at"
    ).fetchall()
    if not rows:
        print("(no sequences)")
        return
    for r in rows:
        print(f"  [{r['status']:12s}] {r['id']:20s} {r['mechanic']:20s} "
              f"solved={r['solved_count']} fail={r['fail_count']}  {r['description']}")


def cmd_sequence_new(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    uid = _uid()
    conn.execute(
        "INSERT INTO sequences (id, mechanic, description, created_at) VALUES (?,?,?,?)",
        (uid, args.mechanic or "", args.description or "", time.time()),
    )
    conn.commit()
    print(f"Created sequence {uid}")


def cmd_sequence_status(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    conn.execute(
        "UPDATE sequences SET status=?, last_tested_at=? WHERE id=?",
        (args.status, time.time(), args.sequence_id),
    )
    if args.status == "SOLVED":
        conn.execute(
            "UPDATE sequences SET solved_count = solved_count + 1 WHERE id=?",
            (args.sequence_id,),
        )
    elif args.status == "FAIL":
        conn.execute(
            "UPDATE sequences SET fail_count = fail_count + 1 WHERE id=?",
            (args.sequence_id,),
        )
    if args.blocked_reason:
        conn.execute(
            "UPDATE sequences SET blocked_reason=? WHERE id=?",
            (args.blocked_reason, args.sequence_id),
        )
    conn.commit()
    print(f"Updated {args.sequence_id} → {args.status}")


def cmd_step_record(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    uid = _uid()
    conn.execute(
        "INSERT INTO steps (id, sequence_id, step_index, action, action_args, status, ts) "
        "VALUES (?,?,?,?,?,?,?)",
        (uid, args.sequence_id, args.step_index, args.action,
         json.dumps(args.action_args or {}), args.status, time.time()),
    )
    conn.commit()
    print(f"Recorded step {uid}")


def cmd_screenshot_link(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    uid = _uid()
    conn.execute(
        "INSERT INTO screenshots (id, step_id, path, hash, kind) VALUES (?,?,?,?,?)",
        (uid, args.step_id, args.path, args.hash, args.kind),
    )
    conn.commit()
    print(f"Linked screenshot {uid}")


def cmd_anomaly_record(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    uid = _uid()
    conn.execute(
        "INSERT INTO anomalies (id, step_id, source, level, category, text, stamp) "
        "VALUES (?,?,?,?,?,?,?)",
        (uid, args.step_id, args.source, args.level, args.category, args.text, args.stamp),
    )
    conn.commit()
    print(f"Recorded anomaly {uid}")


def cmd_checkpoint_save(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    uid = _uid()
    conn.execute(
        "INSERT INTO checkpoints (id, sequence_id, step_index, preset_path, screenshot_ref, ts) "
        "VALUES (?,?,?,?,?,?)",
        (uid, args.sequence_id, args.step_index, args.preset_path, args.screenshot_ref, time.time()),
    )
    conn.commit()
    print(f"Checkpoint saved {uid}")


def cmd_next_to_check(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    row = conn.execute(
        "SELECT id, mechanic, description, status FROM sequences "
        "WHERE status IN ('TO_CHECK', 'BLOCKED') ORDER BY created_at LIMIT 1"
    ).fetchone()
    if row is None:
        print("(all sequences SOLVED)")
        return
    print(f"{row['id']} mechanic={row['mechanic']} status={row['status']}  {row['description']}")


def main() -> None:
    parser = argparse.ArgumentParser(description="MCP Agent Store — external playthrough ledger")
    parser.add_argument("--project", required=True, help="Project identifier")
    parser.add_argument("--store-root", default=DEFAULT_STORE_ROOT, help="Agent store root directory")
    sub = parser.add_subparsers(dest="command")

    p = sub.add_parser("sequence-list")
    p = sub.add_parser("sequence-new")
    p.add_argument("mechanic", nargs="?", default="")
    p.add_argument("description", nargs="?", default="")

    p = sub.add_parser("sequence-status")
    p.add_argument("sequence_id")
    p.add_argument("--status", required=True, choices=STATUS_VALUES)
    p.add_argument("--blocked-reason", default="")

    p = sub.add_parser("step-record")
    p.add_argument("sequence_id")
    p.add_argument("step_index", type=int, default=0)
    p.add_argument("--action", default="")
    p.add_argument("--action-args", type=json.loads, default={})
    p.add_argument("--status", default="TO_CHECK", choices=STATUS_VALUES)

    p = sub.add_parser("screenshot-link")
    p.add_argument("step_id")
    p.add_argument("--path", required=True)
    p.add_argument("--hash", default="")
    p.add_argument("--kind", default="milestone", choices=SCREENSHOT_KINDS)

    p = sub.add_parser("anomaly-record")
    p.add_argument("step_id")
    p.add_argument("--source", default="project")
    p.add_argument("--level", default="warning")
    p.add_argument("--category", default="")
    p.add_argument("--text", default="")
    p.add_argument("--stamp", default="")

    p = sub.add_parser("checkpoint-save")
    p.add_argument("sequence_id")
    p.add_argument("step_index", type=int, default=0)
    p.add_argument("--preset-path", required=True)
    p.add_argument("--screenshot-ref", default="")

    p = sub.add_parser("next-to-check")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    conn = get_conn(args.project, args.store_root)
    try:
        {
            "sequence-list": cmd_sequence_list,
            "sequence-new": cmd_sequence_new,
            "sequence-status": cmd_sequence_status,
            "step-record": cmd_step_record,
            "screenshot-link": cmd_screenshot_link,
            "anomaly-record": cmd_anomaly_record,
            "checkpoint-save": cmd_checkpoint_save,
            "next-to-check": cmd_next_to_check,
        }[args.command](conn, args)
    finally:
        conn.close()


if __name__ == "__main__":
    main()