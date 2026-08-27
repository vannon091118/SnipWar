"""SQLite archive for factual narrative observations."""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Any, Callable

from . import SCHEMA_VERSION
from .errors import ChainValidationError, HistoryChangedError, ImportAtomicityError
from .observe import SourceSnapshot, canonical_json, event_id, observation_digest
from .relationships import build_relationship_events, build_relationship_state, build_character_state
from .beliefs import build_beliefs, build_memory
from .threads import build_threads, current_threads
from .perspectives import build_perspectives, build_conflicts

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
CREATE TABLE IF NOT EXISTS relationship_events (
    relationship_event_id TEXT PRIMARY KEY,
    observation_seq INTEGER NOT NULL,
    source TEXT NOT NULL,
    target TEXT NOT NULL,
    axis TEXT NOT NULL,
    delta REAL NOT NULL,
    reason TEXT NOT NULL,
    evidence_type TEXT NOT NULL,
    rule_version TEXT NOT NULL,
    FOREIGN KEY(observation_seq) REFERENCES observations(seq) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS relationship_state_history (
    relationship_state_id INTEGER PRIMARY KEY AUTOINCREMENT,
    observation_seq INTEGER NOT NULL,
    source TEXT NOT NULL,
    target TEXT NOT NULL,
    values_json TEXT NOT NULL,
    rule_version TEXT NOT NULL,
    FOREIGN KEY(observation_seq) REFERENCES observations(seq) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS character_state_history (
    observation_seq INTEGER NOT NULL,
    character TEXT NOT NULL,
    values_json TEXT NOT NULL,
    rule_version TEXT NOT NULL,
    PRIMARY KEY(observation_seq, character),
    FOREIGN KEY(observation_seq) REFERENCES observations(seq) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS beliefs (
    belief_id TEXT NOT NULL,
    character TEXT NOT NULL,
    subject TEXT NOT NULL,
    claim TEXT NOT NULL,
    confidence REAL NOT NULL,
    formed_at INTEGER NOT NULL,
    last_updated INTEGER NOT NULL,
    evidence_seq INTEGER NOT NULL,
    evidence_type TEXT NOT NULL,
    impact REAL NOT NULL,
    rule_version TEXT NOT NULL,
    PRIMARY KEY(belief_id, evidence_seq),
    FOREIGN KEY(evidence_seq) REFERENCES observations(seq) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS memory (
    memory_id TEXT PRIMARY KEY,
    character TEXT NOT NULL,
    event_seq INTEGER NOT NULL,
    subject TEXT NOT NULL,
    memory_type TEXT NOT NULL,
    emotional_weight REAL NOT NULL,
    retention_weight REAL NOT NULL,
    rule_version TEXT NOT NULL,
    FOREIGN KEY(event_seq) REFERENCES observations(seq) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS threads (
    thread_id TEXT NOT NULL,
    observation_seq INTEGER NOT NULL,
    topic TEXT NOT NULL,
    status TEXT NOT NULL,
    evidence_seq INTEGER NOT NULL,
    rule_version TEXT NOT NULL,
    PRIMARY KEY(thread_id, observation_seq),
    FOREIGN KEY(observation_seq) REFERENCES observations(seq) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS thread_events (
    thread_id TEXT NOT NULL,
    observation_seq INTEGER NOT NULL,
    status TEXT NOT NULL,
    evidence_type TEXT NOT NULL,
    evidence_refs TEXT NOT NULL,
    is_reactivation INTEGER NOT NULL,
    rule_version TEXT NOT NULL,
    PRIMARY KEY(thread_id, observation_seq),
    FOREIGN KEY(observation_seq) REFERENCES observations(seq) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS perspectives (
    perspective_id TEXT PRIMARY KEY,
    character TEXT NOT NULL,
    thread_id TEXT,
    claim TEXT NOT NULL,
    stance TEXT NOT NULL,
    confidence REAL NOT NULL,
    supporting_evidence TEXT NOT NULL,
    contradicting_evidence TEXT NOT NULL,
    rule_version TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS conflicts (
    conflict_id TEXT PRIMARY KEY,
    thread_id TEXT,
    actors TEXT NOT NULL,
    trigger TEXT NOT NULL,
    contradiction TEXT NOT NULL,
    intensity REAL NOT NULL,
    evidence_refs TEXT NOT NULL,
    rule_version TEXT NOT NULL
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
                try:
                    connection.execute("BEGIN")
                    self._write_derived(connection, snapshot.observations)
                    connection.commit()
                except Exception:
                    connection.rollback()
                    raise
                return {"imported": 0, "last_seq": stored_seq, "hash": snapshot.output_hash}
            try:
                connection.execute("BEGIN")
                for count, observation in enumerate(snapshot.observations[stored_seq:], start=1):
                    self._insert_observation(connection, observation)
                    if fail_after is not None and count >= fail_after:
                        raise ImportAtomicityError("injected import failure; transaction rolled back")
                last = snapshot.observations[-1]
                self._write_derived(connection, snapshot.observations)
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

    def _write_derived(self, connection: sqlite3.Connection, observations: list[dict[str, Any]]) -> None:
        for table in ("relationship_events", "relationship_state_history", "character_state_history", "beliefs", "memory", "threads", "thread_events", "perspectives", "conflicts"):
            connection.execute(f"DELETE FROM {table}")
        for item in build_relationship_events(observations):
            connection.execute("INSERT INTO relationship_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", (item["relationship_event_id"], item["observation_seq"], item["source"], item["target"], item["axis"], item["delta"], item["reason"], item["evidence_type"], item["rule_version"]))
        for item in build_relationship_state(observations):
            connection.execute("INSERT INTO relationship_state_history(observation_seq, source, target, values_json, rule_version) VALUES (?, ?, ?, ?, ?)", (item["observation_seq"], item["source"], item["target"], canonical_json(item["values"]), item["rule_version"]))
        for item in build_character_state(observations):
            connection.execute("INSERT INTO character_state_history VALUES (?, ?, ?, ?)", (item["observation_seq"], item["character"], canonical_json(item["values"]), item["rule_version"]))
        for item in build_beliefs(observations):
            connection.execute("INSERT INTO beliefs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", tuple(item.values()))
        for item in build_memory(observations):
            connection.execute("INSERT INTO memory VALUES (?, ?, ?, ?, ?, ?, ?, ?)", tuple(item.values()))
        thread_history = build_threads(observations)
        thread_data = build_threads(observations)
        current_thread_map = {item["thread_id"]: item for item in current_threads(observations)}
        for item in thread_data:
            current = current_thread_map[item["thread_id"]]
            connection.execute("INSERT INTO threads VALUES (?, ?, ?, ?, ?, ?)", (item["thread_id"], item["observation_seq"], current["topic"], item["status"], item["observation_seq"], item["rule_version"]))
            connection.execute("INSERT INTO thread_events VALUES (?, ?, ?, ?, ?, ?, ?)", (item["thread_id"], item["observation_seq"], item["status"], item["evidence_type"], canonical_json(item["evidence_refs"]), int(item["is_reactivation"]), item["rule_version"]))
        perspectives = build_perspectives(observations, build_beliefs(observations), thread_history)
        for item in perspectives:
            connection.execute("INSERT INTO perspectives VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", (item["perspective_id"], item["character"], item["thread_id"], item["claim"], item["stance"], item["confidence"], canonical_json(item["supporting_evidence"]), canonical_json(item["contradicting_evidence"]), item["rule_version"]))
        for item in build_conflicts(perspectives):
            connection.execute("INSERT INTO conflicts VALUES (?, ?, ?, ?, ?, ?, ?, ?)", (item["conflict_id"], item["thread_id"], canonical_json(item["actors"]), item["trigger"], item["contradiction"], item["intensity"], canonical_json(item["evidence_refs"]), item["rule_version"]))

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

    def derived_status(self) -> dict[str, Any]:
        connection = self.connect()
        try:
            self.initialize(connection)
            return {table: int(connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]) for table in ("relationship_events", "relationship_state_history", "character_state_history", "beliefs", "memory", "threads", "thread_events", "perspectives", "conflicts")}
        finally:
            connection.close()

    def status(self) -> dict[str, Any]:
        connection = self.connect()
        try:
            self.initialize(connection)
            meta = dict(connection.execute("SELECT key, value FROM meta"))
            counts = {}
            for table in ("observations", "events", "file_touches", "concept_touches", "relationship_events", "relationship_state_history", "character_state_history", "beliefs", "memory", "threads", "thread_events", "perspectives", "conflicts"):
                counts[table] = int(connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0])
            return {"meta": meta, "counts": counts, "db_path": str(self.db_path)}
        finally:
            connection.close()
