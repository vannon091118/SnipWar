from __future__ import annotations

import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from narrative_runtime.errors import ChainValidationError, HistoryChangedError, ImportAtomicityError
from narrative_runtime.observe import (
    OBSERVATION_FIELDS,
    SourceSnapshot,
    build_observations,
    canonical_json,
    classify_impulse,
    event_id,
    observations_hash,
)
from narrative_runtime.store import Archive


def fixture() -> tuple[dict, dict]:
    chain = {
        "entries": [
            {"seq": 1, "hash": "aaa", "subject": "feat: add navigation", "summary": "feat: add navigation", "narrator": "Sage", "mood": "sachlich", "composite": "c1j1n1a1p1", "p_id": 1, "arc": "a1", "data_changes": [{"file": "a.gd", "insertions": 2, "deletions": 0}]},
            {"seq": 2, "hash": "bbb", "subject": "fix: repair navigation", "summary": "fix: repair navigation", "narrator": "Buffy", "prev_narrator": "Sage", "mood": "trocken", "composite": "c2j2n2a1p1", "p_id": 2, "arc": "a1", "data_changes": [{"file": "a.gd", "insertions": 1, "deletions": 1}], "parent_hashes": ["aaa"]},
            {"seq": 3, "hash": "ccc", "subject": "merge: branch", "summary": "merge: branch", "narrator": "Thinker", "prev_narrator": "Buffy", "mood": "warm", "composite": "c3j3n3a1p2", "p_id": 3, "arc": "a1", "data_changes": [{"file": "b.gd", "insertions": 3, "deletions": 0}], "parent_hashes": ["bbb", "other"]},
        ],
        "repairs": [],
    }
    index = {"commits": {"aaa": {"entities": ["F-1"]}, "bbb": {"entities": ["F-1", "C-1"]}, "ccc": {"entities": ["C-1"]}}}
    return chain, index


class RuntimeTests(unittest.TestCase):
    def test_classification_precedence(self):
        self.assertEqual(classify_impulse("Doku: fix it"), "DOKU")
        self.assertEqual(classify_impulse("fix: repair it"), "FIX")
        self.assertEqual(classify_impulse("kurz"), "TRIVIAL")
        self.assertEqual(classify_impulse("ship systems expand and evolve"), "CODE")

    def test_observation_purity_and_projection(self):
        chain, index = fixture()
        observations = build_observations(chain, index)
        self.assertEqual(len(observations), 3)
        self.assertEqual(observations[1]["impulse_category_recomputed"], "FIX")
        self.assertTrue(observations[1]["subject_term_flags"]["repair"])
        self.assertEqual(observations[2]["parent_hashes"], ["bbb", "other"])
        self.assertEqual(observations[1]["prior_file_touchers"]["a.gd"], [1])
        self.assertEqual(observations[1]["shared_entities"]["F-1"], [1])
        forbidden = {"emotion", "blame", "intention", "interpretation", "belief", "responsibility"}
        for observation in observations:
            self.assertTrue(set(observation) <= OBSERVATION_FIELDS)
            self.assertTrue(forbidden.isdisjoint(observation))

    def test_deterministic_hash_and_event_id(self):
        chain, index = fixture()
        first = build_observations(chain, index)
        second = build_observations(json.loads(json.dumps(chain)), json.loads(json.dumps(index)))
        self.assertEqual(first, second)
        self.assertEqual(observations_hash(first), observations_hash(second))
        self.assertEqual(event_id(1, "aaa"), event_id(1, "aaa"))
        self.assertNotEqual(event_id(1, "aaa"), event_id(1, "changed"))

    def test_gap_rejected(self):
        chain, index = fixture()
        chain["entries"][1]["seq"] = 4
        with self.assertRaises(ChainValidationError):
            build_observations(chain, index)

    def test_import_idempotent_and_rebuild_equal(self):
        chain, index = fixture()
        with tempfile.TemporaryDirectory() as temp:
            snapshot = _snapshot(temp, chain, index)
            archive = Archive(Path(temp) / "db.sqlite")
            first = archive.import_snapshot(snapshot)
            second = archive.import_snapshot(snapshot)
            self.assertEqual(first["imported"], 3)
            self.assertEqual(second["imported"], 0)
            self.assertTrue(archive.verify(snapshot))
            dump_before = archive.dump_observations()
            archive.rebuild(snapshot)
            self.assertEqual(dump_before, archive.dump_observations())
            self.assertTrue(archive.verify(snapshot))

    def test_amend_anchor_rejected(self):
        chain, index = fixture()
        with tempfile.TemporaryDirectory() as temp:
            snapshot = _snapshot(temp, chain, index)
            archive = Archive(Path(temp) / "db.sqlite")
            archive.import_snapshot(snapshot)
            changed = json.loads(json.dumps(chain))
            changed["entries"][1]["hash"] = "rewritten"
            changed_snapshot = _snapshot(temp, changed, index)
            with self.assertRaises(HistoryChangedError):
                archive.import_snapshot(changed_snapshot)
            archive.rebuild(changed_snapshot)
            self.assertTrue(archive.verify(changed_snapshot))

    def test_atomic_failure_leaves_empty_archive(self):
        chain, index = fixture()
        with tempfile.TemporaryDirectory() as temp:
            snapshot = _snapshot(temp, chain, index)
            archive = Archive(Path(temp) / "db.sqlite")
            with self.assertRaises(ImportAtomicityError):
                archive.import_snapshot(snapshot, fail_after=2)
            self.assertEqual(archive.status()["counts"]["events"], 0)
            self.assertEqual(archive.meta(), {})

    def test_incremental_equals_rebuild(self):
        chain, index = fixture()
        with tempfile.TemporaryDirectory() as temp:
            full = _snapshot(temp, chain, index)
            archive_incremental = Archive(Path(temp) / "incremental.sqlite")
            # Observation projection is defined over the complete source chain
            # (next_narrator and sequence facts may look ahead). The archive can
            # still be filled in two transactions by importing observation
            # prefixes, but both prefixes must come from this same full snapshot.
            prefix = SourceSnapshot(full.chain, full.index, full.observations[:1], full.output_hash)
            archive_incremental.import_snapshot(prefix)
            archive_incremental.import_snapshot(full)
            archive_rebuild = Archive(Path(temp) / "rebuild.sqlite")
            archive_rebuild.rebuild(full)
            self.assertEqual(archive_incremental.dump_observations(), archive_rebuild.dump_observations())
            self.assertEqual(archive_incremental.meta(), archive_rebuild.meta())


def _snapshot(temp: str, chain: dict, index: dict) -> SourceSnapshot:
    chain_path = Path(temp) / "chain.json"
    index_path = Path(temp) / "index.json"
    chain_path.write_text(canonical_json(chain), encoding="utf-8")
    index_path.write_text(canonical_json(index), encoding="utf-8")
    return SourceSnapshot.from_paths(chain_path, index_path)


if __name__ == "__main__":
    unittest.main()
