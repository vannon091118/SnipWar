"""SQLite archive for factual narrative observations."""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Any, Callable

from . import SCHEMA_VERSION
from .errors import ChainValidationError, HistoryChangedError, ImportAtomicityError
from .observe import SourceSnapshot, canonical_json, event_id, observation_digest

META_KEYS = (
    "schema_version",
    "last_processed_chain_seq",
    "last_processed_chain_hash",
    "last_processed_entry_digest",
    "observation_output_hash",
)

SCHEMA_SQL = """
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS observations (
    seq INTEGER PRIMARY KEY,
    commit_hash TEXT NOT NULL,
    observation_digest TEXT NOT NULL,
    observation_json TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS events (
    event_id TEXT PRIMARY KEY,
    seq INTEGER NOT NULL UNIQUE,
    commit_hash TEXT NOT NULL,
    event_type TEXT NOT NULL,
    subject TEXT NOT NULL,
    narrator TEXT NOT NULL,
    prev_narrator TEXT,
    impulse_category TEXT,
    entry_digest TEXT NOT NULL,
    date TEXT
);
CREATE TABLE IF NOT EXISTS event_participants (
    event_id TEXT NOT NULL,
    participant_type TEXT NOT NULL,
    participant_id TEXT NOT NULL,
    PRIMARY KEY(event_id, participant_type, participant_id),
    FOREIGN KEY(event_id) REFERENCES events(event_id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS event_evidence (
    event_id TEXT NOT NULL,
    evidence_seq INTEGER NOT NULL,
    evidence_type TEXT NOT NULL,
    PRIMARY KEY(event_id, evidence_seq, evidence_type),
    FOREIGN KEY(event_id) REFERENCES events(event_id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS file_touches (
    seq INTEGER NOT NULL,
    path TEXT NOT NULL,
    event_id TEXT NOT NULL,
    insertions INTEGER,
    deletions INTEGER,
    prior_touch_seqs TEXT NOT NULL,
    PRIMARY KEY(seq, path),
    FOREIGN KEY(event_id) REFERENCES events(event_id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS concept_touches (
    seq INTEGER NOT NULL,
    entity_id TEXT NOT NULL,
    event_id TEXT NOT NULL,
    prior_touch_seqs TEXT NOT NULL,
    PRIMARY KEY(seq, entity_id),
    FOREIGN KEY(event_id) REFERENCES events(event_id) ON DELETE CASCADE
);
"""


class Archive:
    def __init__(self, db_path: Path):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)

    def connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.db_path)
        connection.execute("PRAGMA foreign_keys = ON")
        return connection

    def initialize(self, connection: sqlite3.Connection) -> None:
        connection.executescript(SCHEMA_SQL)

    def meta(self) -> dict[str, str]:
        connection = self.connect()
        try:
            self.initialize(connection)
            return dict(connection.execute("SELECT key, value FROM meta"))
        finally:
            connection.close()

    def _validate_anchor(self, connection: sqlite3.Connection, snapshot: SourceSnapshot) -> int:
        values = dict(connection.execute("SELECT key, value FROM meta"))
        stored_seq = int(values.get("last_processed_chain_seq", "0"))
        stored_rows = connection.execute(
            """SELECT observations.seq, observations.commit_hash, events.entry_digest
               FROM observations JOIN events ON events.seq = observations.seq
               ORDER BY observations.seq"""
        ).fetchall()
        if stored_seq <= 0:
            if stored_rows:
                raise HistoryChangedError("HISTORY CHANGED: archive rows exist without a chain anchor; rebuild required")
            return 0
        if stored_seq > len(snapshot.observations):
            raise HistoryChangedError("HISTORY CHANGED: stored chain is ahead; rebuild required")
        if len(stored_rows) != stored_seq:
            raise HistoryChangedError("HISTORY CHANGED: archive prefix is incomplete; rebuild required")
        # Check the complete imported prefix, not just its final row.  A rewrite
        # before the head must also invalidate incremental import.
        for row in stored_rows:
            seq = int(row[0])
            current = snapshot.observations[seq - 1]
            if row[1] != current["commit_hash"] or row[2] != current["entry_digest"]:
                raise HistoryChangedError(
                    f"HISTORY CHANGED at seq {seq}: imported prefix differs; rebuild required"
                )
        current = snapshot.observations[stored_seq - 1]
        current_hash = current["commit_hash"]
        current_digest = str(current["entry_digest"])
        if values.get("last_processed_chain_hash") != current_hash or values.get("last_processed_entry_digest") != current_digest:
            raise HistoryChangedError(
                f"HISTORY CHANGED at seq {stored_seq}: chain anchor differs; rebuild required"
            )
        return stored_seq

    def import_snapshot(self, snapshot: SourceSnapshot, fail_after: int | None = None) -> dict[str, Any]:
        connection = self.connect()
        try:
            self.initialize(connection)
            stored_seq = self._validate_anchor(connection, snapshot)
            if stored_seq > len(snapshot.observations):
                raise HistoryChangedError("HISTORY CHANGED: stored chain is ahead; rebuild required")
            if stored_seq == len(snapshot.observations):
                return {"imported": 0, "last_seq": stored_seq, "hash": snapshot.output_hash}
            try:
                connection.execute("BEGIN")
                for count, observation in enumerate(snapshot.observations[stored_seq:], start=1):
                    self._insert_observation(connection, observation)
                    if fail_after is not None and count >= fail_after:
                        raise ImportAtomicityError("injected import failure; transaction rolled back")
                last = snapshot.observations[-1]
                self._set_meta(connection, {
                    "schema_version": SCHEMA_VERSION,
                    "last_processed_chain_seq": int(last["seq"]),
                    "last_processed_chain_hash": last["commit_hash"],
                    "last_processed_entry_digest": last["entry_digest"],
                    "observation_output_hash": snapshot.output_hash,
                })
                connection.commit()
            except Exception:
                connection.rollback()
                raise
            return {"imported": len(snapshot.observations) - stored_seq, "last_seq": int(last["seq"]), "hash": snapshot.output_hash}
        finally:
            connection.close()

    def _insert_observation(self, connection: sqlite3.Connection, observation: dict[str, Any]) -> None:
        seq = int(observation["seq"])
        eid = event_id(seq, observation["commit_hash"])
        connection.execute(
            "INSERT OR REPLACE INTO observations(seq, commit_hash, observation_digest, observation_json) VALUES (?, ?, ?, ?)",
            (seq, observation["commit_hash"], observation_digest(observation), canonical_json(observation)),
        )
        connection.execute(
            """INSERT OR REPLACE INTO events(event_id, seq, commit_hash, event_type, subject, narrator,
               prev_narrator, impulse_category, entry_digest, date) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (eid, seq, observation["commit_hash"], "commit_observed", observation["subject"], observation["narrator"],
             observation.get("prev_narrator"), observation.get("impulse_category_recomputed"), observation["entry_digest"], observation["date"]),
        )
        connection.execute("DELETE FROM event_participants WHERE event_id = ?", (eid,))
        participants = [("narrator", observation["narrator"])]
        if observation.get("prev_narrator"):
            participants.append(("prev_narrator", str(observation["prev_narrator"])))
        connection.executemany("INSERT INTO event_participants VALUES (?, ?, ?)", [(eid, kind, name) for kind, name in participants])
        connection.execute("DELETE FROM event_evidence WHERE event_id = ?", (eid,))
        connection.execute("INSERT INTO event_evidence VALUES (?, ?, ?)", (eid, seq, "observation"))
        connection.execute("DELETE FROM file_touches WHERE seq = ?", (seq,))
        file_changes: dict[str, dict[str, int]] = {}
        for change in observation["data_changes"]:
            path = str(change.get("file", ""))
            if not path:
                continue
            totals = file_changes.setdefault(path, {"insertions": 0, "deletions": 0})
            totals["insertions"] += int(change.get("insertions", 0))
            totals["deletions"] += int(change.get("deletions", 0))
        for path in sorted(file_changes):
            totals = file_changes[path]
            connection.execute(
                "INSERT INTO file_touches VALUES (?, ?, ?, ?, ?, ?)",
                (seq, path, eid, totals["insertions"], totals["deletions"], canonical_json(observation["prior_file_touchers"].get(path, []))),
            )
        connection.execute("DELETE FROM concept_touches WHERE seq = ?", (seq,))
        for entity in observation["entities"]:
            connection.execute(
                "INSERT INTO concept_touches VALUES (?, ?, ?, ?)",
                (seq, entity, eid, canonical_json(observation["shared_entities"].get(entity, []))),
            )

    def _set_meta(self, connection: sqlite3.Connection, values: dict[str, Any]) -> None:
        connection.executemany(
            "INSERT INTO meta(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            [(key, str(value)) for key, value in values.items()],
        )

    def rebuild(self, snapshot: SourceSnapshot) -> dict[str, Any]:
        connection = self.connect()
        connection.close()
        if self.db_path.exists():
            self.db_path.unlink()
        return self.import_snapshot(snapshot)

    def dump_observations(self) -> list[dict[str, Any]]:
        connection = self.connect()
        try:
            self.initialize(connection)
            rows = connection.execute(
                "SELECT observation_json FROM observations ORDER BY seq"
            ).fetchall()
            return [json.loads(row[0]) for row in rows]
        finally:
            connection.close()

    def verify(self, snapshot: SourceSnapshot) -> bool:
        values = self.meta()
        stored = self.dump_observations()
        if stored != snapshot.observations:
            return False
        if values.get("observation_output_hash") != snapshot.output_hash:
            return False
        if int(values.get("last_processed_chain_seq", "0")) != len(snapshot.observations):
            return False
        if not snapshot.observations:
            return not values.get("last_processed_chain_seq")
        return (
            values.get("last_processed_chain_hash") == snapshot.observations[-1]["commit_hash"]
            and values.get("last_processed_entry_digest") == snapshot.observations[-1]["entry_digest"]
        )

    def status(self) -> dict[str, Any]:
        connection = self.connect()
        try:
            self.initialize(connection)
            meta = dict(connection.execute("SELECT key, value FROM meta"))
            counts = {}
            for table in ("observations", "events", "file_touches", "concept_touches"):
                counts[table] = int(connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0])
            return {"meta": meta, "counts": counts, "db_path": str(self.db_path)}
        finally:
            connection.close()
