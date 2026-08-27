"""Read-only context bridge from the derived archive to DOKI."""

from __future__ import annotations

from typing import Any

from .observe import SourceSnapshot

CONTEXT_SCHEMA = "narrative_context/v1"


class ContextUnavailable(Exception):
    """Context cannot be safely used; callers must use the DOKI fallback."""


def build_context(archive: Any, snapshot: SourceSnapshot) -> dict[str, Any]:
    """Return context only when the archive exactly represents ``snapshot``.

    This function never writes source files, recalculates a Composite, or selects
    a narrator.  A missing, empty, stale, or invalid archive is explicitly
    unavailable so DOKI can retain its existing behavior.
    """
    if not archive.verify(snapshot):
        raise ContextUnavailable("narrative context is unavailable or stale")
    observations = archive.dump_observations()
    if not observations:
        raise ContextUnavailable("narrative context has no observations")
    head = observations[-1]
    derived = archive.derived_status()
    return {
        "schema": CONTEXT_SCHEMA,
        "chain_seq": int(head["seq"]),
        "chain_hash": head["commit_hash"],
        "observation_output_hash": snapshot.output_hash,
        "facts": {
            "seq": int(head["seq"]),
            "commit_hash": head["commit_hash"],
            "subject": head["subject"],
            "summary": head["summary"],
            "files": head["files"],
            "entities": head["entities"],
            "mood": head["mood"],
            "composite": head["composite"],
        },
        "current_character": head["narrator"],
        "current_state": {
            "relationship_events": derived["relationship_events"],
            "character_state_snapshots": derived["character_state_history"],
        },
        "relevant_relationships": {
            "relationship_events": derived["relationship_events"],
            "relationship_state_snapshots": derived["relationship_state_history"],
        },
        "beliefs": {"count": derived["beliefs"]},
        "memory_refs": {"count": derived["memory"]},
        "threads": {"count": derived["threads"], "thread_events": derived["thread_events"]},
        "conflicts": {"count": derived["conflicts"]},
        "allowed_interpretations": [
            "Use only the supplied facts and evidence references.",
            "Do not alter the Composite or narrator selection.",
        ],
    }
