"""Factual, deterministic projections of the DOKI chain.

This module deliberately does not infer emotion, responsibility, intention, or
belief.  It only copies source facts and computes named mechanical projections.
"""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from . import OBSERVATION_SCHEMA, SCHEMA_VERSION
from .errors import ChainValidationError

SCHEMA = OBSERVATION_SCHEMA
PROJECTION_RULES = {
    "impulse_category_recomputed": "classify_impulse/v1",
    "subject_term_flags": "subject_terms/v1",
    "is_merge": "merge_rule/v1",
    "files": "files_rule/v1",
    "prior_file_touchers": "prior_touchers/v1",
    "file_seq_gaps": "seq_gap/v1",
    "shared_entities": "shared_entities/v1",
}

# This is the exact precedence and vocabulary of DOKI_VoiceComposer.classify_impulse.
_TERM_GROUPS = {
    "doc": r"\b(doku|archiv|changelog|readme|plan|comment|docs)\b",
    "repair": r"\b(fix|bug|hotfix|patch|repair|fehler|korr)\b",
    "refactor": r"\b(restruktur|refactor|cleanup|aufr|umstruktur|moved|verschoben|modular|extract|dedupli)",
    "build": r"\b(build|commitlayer|commit_layer|author.system|hook|verifier|pipeline|doki)\b",
    "test": r"\b(test|test\w*)\b",
}

# Fields admitted by the factual/projection contract. Unknown fields are rejected.
OBSERVATION_FIELDS = frozenset(
    {
        "schema", "schema_version", "seq", "commit_hash", "entry_digest", "date",
        "subject", "summary", "narrator", "prev_narrator", "mood", "composite",
        "composite_fields", "parent_hashes", "p_id", "arc", "impulse_category", "seeded", "model_id",
        "data_changes", "entities", "files", "impulse_category_recomputed",
        "subject_term_flags", "is_merge", "prior_file_touchers", "file_seq_gaps",
        "shared_entities", "sequence_facts", "merge_facts", "sideplot_facts", "projection_rules",
    }
)


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def digest_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def event_id(seq: int, commit_hash: str, schema_version: int = SCHEMA_VERSION) -> str:
    raw = f"{seq}|{commit_hash}|{schema_version}".encode("utf-8")
    return "ev_" + hashlib.sha256(raw).hexdigest()[:16]


def classify_impulse(text: str) -> str:
    """Exact Python port of DOKI's first-match impulse classification."""
    lower = text.lower()
    if re.search(_TERM_GROUPS["doc"], lower):
        return "DOKU"
    if re.search(_TERM_GROUPS["repair"], lower):
        return "FIX"
    if re.search(_TERM_GROUPS["refactor"], lower):
        return "REFACTOR"
    if re.search(_TERM_GROUPS["build"], lower):
        return "BUILD"
    if re.search(_TERM_GROUPS["test"], lower):
        return "TEST-ASSET"
    if len(text) < 12 or len(text.split(" ")) <= 2:
        return "TRIVIAL"
    return "CODE"


def composite_fields(composite: str) -> dict[str, int]:
    match = re.fullmatch(r"c(\d+)j(\d+)n(\d+)a(\d+)p(\d+)", composite or "")
    if not match:
        return {}
    names = ("c", "j", "n", "a", "p")
    return {name: int(value) for name, value in zip(names, match.groups())}


def _source_entities(entry: dict[str, Any], index: dict[str, Any]) -> list[str]:
    commit = index.get("commits", {}).get(str(entry.get("hash", "")), {})
    return sorted({str(value) for value in commit.get("entities", [])})


def _raw_files(entry: dict[str, Any]) -> list[str]:
    return sorted(
        {str(change.get("file", "")) for change in entry.get("data_changes", []) if change.get("file")}
    )


def _subject_flags(subject: str) -> dict[str, bool]:
    lower = subject.lower()
    return {
        "doc": re.search(_TERM_GROUPS["doc"], lower) is not None,
        "repair": re.search(_TERM_GROUPS["repair"], lower) is not None,
        "refactor": re.search(_TERM_GROUPS["refactor"], lower) is not None,
        "build": re.search(_TERM_GROUPS["build"], lower) is not None,
        "test": re.search(_TERM_GROUPS["test"], lower) is not None,
        "merge": lower.startswith("merge"),
    }


def _validate_contiguous(entries: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    ordered = sorted(entries, key=lambda item: int(item.get("seq", 0)))
    expected = list(range(1, len(ordered) + 1))
    actual = [int(item.get("seq", 0)) for item in ordered]
    if actual != expected:
        raise ChainValidationError(f"CHAIN_GAP: expected sequences 1..{len(ordered)}, got {actual[:10]}...")
    return ordered


def load_sources(chain_path: Path, index_path: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    try:
        chain = json.loads(chain_path.read_text(encoding="utf-8"))
        index = json.loads(index_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ChainValidationError(f"cannot read source chain/index: {exc}") from exc
    if not isinstance(chain.get("entries"), list):
        raise ChainValidationError("CHAIN_INVALID: entries must be an array")
    _validate_contiguous(chain["entries"])
    return chain, index


def build_observations(chain: dict[str, Any], index: dict[str, Any]) -> list[dict[str, Any]]:
    entries = _validate_contiguous(chain.get("entries", []))
    prior_files: dict[str, list[int]] = {}
    prior_entities: dict[str, list[int]] = {}
    observations: list[dict[str, Any]] = []

    for entry_index, entry in enumerate(entries):
        seq = int(entry["seq"])
        subject = str(entry.get("subject", entry.get("summary", "")))
        summary = str(entry.get("summary", subject))
        commit_hash = str(entry.get("hash", entry.get("commit_hash", "")))
        files = _raw_files(entry)
        entities = _source_entities(entry, index)
        prior_file_touchers = {
            path: list(reversed(prior_files[path][-5:])) for path in files if prior_files.get(path)
        }
        file_seq_gaps = {
            path: seq - prior_files[path][-1] for path in files if prior_files.get(path)
        }
        shared_entities = {
            entity: list(reversed(prior_entities[entity][-5:]))
            for entity in entities if prior_entities.get(entity)
        }
        composite = str(entry.get("composite", ""))
        is_merge = subject.lower().startswith("merge")
        parent_hashes = entry.get("parent_hashes", [])
        if not isinstance(parent_hashes, list):
            raise ChainValidationError(f"CHAIN_INVALID: parent_hashes at seq {seq} must be an array")
        parent_hashes = [str(value) for value in parent_hashes]
        repair_markers = [
            repair for repair in chain.get("repairs", [])
            if isinstance(repair, dict) and str(repair.get("at_hash", "")) == commit_hash
        ]
        observation = {
            "schema": SCHEMA,
            "schema_version": SCHEMA_VERSION,
            "seq": seq,
            "commit_hash": commit_hash,
            "entry_digest": digest_json(entry),
            "date": str(entry.get("date", "")),
            "subject": subject,
            "summary": summary,
            "narrator": str(entry.get("narrator", "")),
            "prev_narrator": entry.get("prev_narrator"),
            "mood": str(entry.get("mood", "")),
            "composite": composite,
            "composite_fields": composite_fields(composite),
            "parent_hashes": parent_hashes,
            "p_id": int(entry.get("p_id", 0)),
            "arc": str(entry.get("arc", "")),
            "impulse_category": entry.get("impulse_category"),
            "seeded": bool(entry.get("seeded", False)),
            "model_id": str(entry.get("model_id", "")),
            "data_changes": entry.get("data_changes", []),
            "entities": entities,
            "files": files,
            "impulse_category_recomputed": classify_impulse(subject),
            "subject_term_flags": _subject_flags(subject),
            "is_merge": is_merge,
            "prior_file_touchers": prior_file_touchers,
            "file_seq_gaps": file_seq_gaps,
            "shared_entities": shared_entities,
            "sequence_facts": {
                "prior_seqs": list(range(1, seq)),
                "prior_repair_seqs": [
                    int(previous["seq"])
                    for previous in entries[:entry_index]
                    if _subject_flags(str(previous.get("subject", previous.get("summary", ""))))["repair"]
                ],
            },
            "merge_facts": {
                "subject_starts_merge": is_merge,
                "parent_count": len(parent_hashes),
                "parent_hashes_present": "parent_hashes" in entry,
            },
            "sideplot_facts": {
                "reanchor_marker_count": len(repair_markers),
                "reanchor_markers": repair_markers,
            },
            "projection_rules": PROJECTION_RULES,
        }
        unknown = set(observation) - OBSERVATION_FIELDS
        if unknown:
            raise ChainValidationError(f"OBSERVATION_SCHEMA: unknown fields {sorted(unknown)}")
        observations.append(observation)
        for path in files:
            prior_files.setdefault(path, []).append(seq)
        for entity in entities:
            prior_entities.setdefault(entity, []).append(seq)
    return observations


def observations_json(observations: list[dict[str, Any]]) -> str:
    return canonical_json(sorted(observations, key=lambda item: int(item["seq"])))


def observations_hash(observations: list[dict[str, Any]]) -> str:
    return hashlib.sha256(observations_json(observations).encode("utf-8")).hexdigest()


def observation_digest(observation: dict[str, Any]) -> str:
    return digest_json(observation)


@dataclass(frozen=True)
class SourceSnapshot:
    chain: dict[str, Any]
    index: dict[str, Any]
    observations: list[dict[str, Any]]
    output_hash: str

    @classmethod
    def from_paths(cls, chain_path: Path, index_path: Path) -> "SourceSnapshot":
        chain, index = load_sources(chain_path, index_path)
        observations = build_observations(chain, index)
        return cls(chain, index, observations, observations_hash(observations))

    @property
    def entries(self) -> list[dict[str, Any]]:
        return sorted(self.chain["entries"], key=lambda item: int(item["seq"]))
