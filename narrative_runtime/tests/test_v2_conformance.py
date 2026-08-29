"""V2 conformance tests for the closed contract gaps (G5/G6/G7/G8/G9/G11/G12/G16/G19).

Each test proves a specific V2 contract point. "Code exists" is not enough —
these tests verify behavior, determinism, and auditability.
"""

from __future__ import annotations

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from narrative_runtime.beliefs import (
    BELIEF_BASES,
    BELIEF_STATUSES,
    build_beliefs,
    build_memory,
)
from narrative_runtime.observe import SourceSnapshot, canonical_json
from narrative_runtime.personality import PERSONALITIES, all_personalities
from narrative_runtime.public_state import AXES, build_public_state
from narrative_runtime.relationships import (
    CHARACTER_AXES,
    DECAY,
    NARRATORS,
    RELATIONSHIP_AXES,
    build_character_state,
    build_relationship_effects,
    build_relationship_state,
    classify_events,
)
from narrative_runtime.spotlight import (
    BALANCE_LOWER,
    BALANCE_UPPER,
    MAX_WEIGHT,
    MIN_WEIGHT,
    SOCIAL_LOWER,
    SOCIAL_UPPER,
    select_narrator,
)
from narrative_runtime.store import Archive
from narrative_runtime.threads import build_threads, current_threads


def observation(seq: int, subject: str, narrator: str = "Buffy", previous: str = "Thinker",
                files: list[str] | None = None, entities: list[str] | None = None,
                arc: str = "a1", composite: str | None = None) -> dict:
    return {
        "seq": seq,
        "subject": subject,
        "summary": subject,
        "narrator": narrator,
        "prev_narrator": previous,
        "files": files or ["a.gd"],
        "entities": entities or [],
        "arc": arc,
        "composite": composite or f"c{seq}j1n{(seq % 14) + 1}a1p1",
        "subject_term_flags": {
            "repair": subject.lower().startswith("fix"),
            "test": "test" in subject.lower(),
            "merge": subject.lower().startswith("merge"),
            "doc": subject.lower().startswith(("doku", "doc")),
        },
        "relationship_facts": {
            "explicit_admission": "my mistake" in subject.lower(),
            "explicit_disagreement": "disagree" in subject.lower(),
            "explicit_revert": "revert" in subject.lower(),
            "explicit_causality": "broken by" in subject.lower() or "caused by" in subject.lower(),
            "stance": "minimal" if "minimal" in subject.lower() else None,
        },
        "is_merge": subject.lower().startswith("merge"),
        "mood": "sachlich",
    }


class BeliefsConformanceTests(unittest.TestCase):
    def test_beliefs_have_basis_and_status(self):
        obs = [observation(1, "feat: add navigation"), observation(2, "feat: more navigation")]
        beliefs = build_beliefs(obs)
        self.assertTrue(beliefs)
        for belief in beliefs:
            self.assertIn(belief["basis"], BELIEF_BASES)
            self.assertIn(belief["status"], BELIEF_STATUSES)
        # First formation is FACT (raw observation facts) and active
        self.assertEqual(beliefs[0]["basis"], "FACT")
        self.assertEqual(beliefs[0]["status"], "active")
        # Supporting evidence strengthens
        self.assertEqual(beliefs[-1]["status"], "strengthened")
        self.assertEqual(beliefs[-1]["last_reinforced"], 2)

    def test_counter_evidence_disproves_and_keeps_basis(self):
        first = observation(1, "feat: add navigation")
        counter = observation(2, "rebuttal: change process")
        counter["counter_evidence"] = {"subject": "change_process", "evidence_type": "contradicts"}
        beliefs = build_beliefs([first, counter])
        disproven = [b for b in beliefs if b["evidence_type"] == "contradicts"]
        self.assertTrue(disproven)
        self.assertEqual(disproven[0]["status"], "disproven")
        self.assertLess(disproven[0]["confidence"], beliefs[0]["confidence"])
        # Counter-evidence is a deterministic projection, not a raw fact
        self.assertEqual(disproven[0]["basis"], "INFERRED")
        # SOCIAL is reserved and never produced without external input
        self.assertNotIn("SOCIAL", {b["basis"] for b in beliefs})

    def test_beliefs_are_deterministic(self):
        obs = [observation(1, "fix: repair a"), observation(2, "fix: repair a"), observation(3, "feat: x")]
        self.assertEqual(build_beliefs(obs), build_beliefs(obs))


class MemoryConformanceTests(unittest.TestCase):
    def test_memory_has_involved_and_recall(self):
        obs = [
            observation(1, "feat: add navigation", files=["nav.gd"], entities=["NAV"]),
            observation(2, "fix: repair navigation", narrator="Devin", previous="Buffy", files=["nav.gd"], entities=["NAV"]),
            observation(3, "feat: unrelated", files=["other.gd"]),
        ]
        memory = build_memory(obs)
        by_seq = {m["event_seq"]: m for m in memory}
        # involved lists everyone present in the event
        self.assertEqual(set(by_seq[2]["involved"]), {"Buffy", "Devin"})
        self.assertEqual(set(by_seq[1]["involved"]), {"Buffy", "Thinker"})
        # seq 1 is recalled by seq 2 (shared file/entity); seq 3 never recalls
        self.assertEqual(by_seq[1]["recall_count"], 1)
        self.assertEqual(by_seq[1]["last_recalled"], 2)
        self.assertEqual(by_seq[3]["recall_count"], 0)
        self.assertIsNone(by_seq[3]["last_recalled"])

    def test_memory_replayable_and_event_unchanged(self):
        obs = [observation(1, "feat: a", files=["a.gd"]), observation(2, "fix: a", files=["a.gd"])]
        first = canonical_json(obs[0])
        memory = build_memory(obs)
        self.assertEqual(canonical_json(obs[0]), first)
        self.assertEqual(memory, build_memory(obs))


class ThreadsConformanceTests(unittest.TestCase):
    def test_threads_have_relevance_separate_from_pressure(self):
        obs = [
            observation(1, "feat: a", files=["a.gd"]),
            observation(2, "feat: a", files=["a.gd"]),
            observation(3, "disagree: reject a", narrator="Devin", previous="Buffy", files=["a.gd"]),
        ]
        events = build_threads(obs)
        self.assertTrue(all("relevance" in e for e in events))
        self.assertTrue(all(0.0 <= e["relevance"] <= 1.0 for e in events))
        threads = current_threads(obs)
        self.assertTrue(all("pressure" in t and "relevance" in t for t in threads))
        # pressure and relevance are distinct fields with distinct semantics
        for thread in threads:
            self.assertNotEqual(thread["pressure"], thread["relevance"])

    def test_thread_relevance_is_deterministic(self):
        obs = [observation(1, "feat: a", files=["a.gd"]), observation(2, "fix: a", files=["a.gd"])]
        self.assertEqual(current_threads(obs), current_threads(obs))


class DecayConformanceTests(unittest.TestCase):
    def test_axis_specific_decay_order(self):
        # irritation decays fastest, trust damage slowest
        self.assertLess(DECAY["irritation"], DECAY["defensiveness"])
        self.assertLess(DECAY["defensiveness"], DECAY["resentment"])
        self.assertLess(DECAY["resentment"], DECAY["trust"])
        self.assertLess(DECAY["trust"], 1.0)

    def test_decay_is_not_uniform_reset(self):
        # One damage event, then 29 quiet commits. Irritation must return to
        # baseline quickly (fast decay); trust damage must persist (slow decay).
        # Axes must NOT all collapse to 0.5 at the same rate.
        quiet = [observation(i, "feat: quiet work", files=["a.gd"]) for i in range(2, 31)]
        many = build_relationship_state([
            observation(1, "feat: add docs", files=["a.gd"]),
            observation(2, "revert: restore docs broken by prior change", files=["a.gd"]),
            *quiet,
        ])
        head = [i for i in many if i["observation_seq"] == 30 and i["source"] == "Buffy" and i["target"] == "Thinker"]
        self.assertEqual(len(head), 1)
        values = head[0]["values"]
        # irritation is closer to baseline than trust (fast vs slow decay)
        self.assertLess(abs(values["irritation"] - 0.5), abs(values["trust"] - 0.5))
        self.assertLess(values["trust"], 0.5)

    def test_raw_events_survive_decay(self):
        # Decay touches state, never the event history itself.
        obs = [observation(1, "disagree: reject x", files=["a.gd"])] * 5
        effects = build_relationship_effects(obs)
        self.assertEqual(len(effects), 5)
        # Effects keep their original delta values
        self.assertTrue(all(x["delta"] != 0.0 for x in effects))


class CharacterStateConformanceTests(unittest.TestCase):
    def test_fatigue_axis_exists(self):
        obs = [observation(1, "feat: a")]
        snapshots = build_character_state(obs)
        self.assertTrue(snapshots)
        self.assertIn("fatigue", CHARACTER_AXES)
        self.assertTrue(all("fatigue" in s["values"] for s in snapshots))

    def test_prev_only_changes_with_interaction_evidence(self):
        # Narrator selection alone must not change prev_narrator's state.
        obs = [observation(1, "feat: a", narrator="Buffy", previous="Thinker")]
        snapshots = build_character_state(obs)
        buffy = [s for s in snapshots if s["character"] == "Buffy"]
        thinker = [s for s in snapshots if s["character"] == "Thinker"]
        self.assertTrue(buffy)
        # No interaction class → Thinker untouched
        self.assertEqual(thinker, [])
        # With explicit disagreement (needs prior stance evidence), prev IS affected
        obs2 = [
            observation(1, "proposal: minimal docs", narrator="Buffy", previous="Thinker", files=["a.gd"]),
            observation(2, "disagree: reject minimal docs", narrator="Devin", previous="Buffy", files=["a.gd"]),
        ]
        snapshots2 = build_character_state(obs2)
        devin2 = [s for s in snapshots2 if s["character"] == "Devin" and s["observation_seq"] == 2]
        buffy2 = [s for s in snapshots2 if s["character"] == "Buffy" and s["observation_seq"] == 2]
        # Narrator (Devin) reacts with defensiveness
        self.assertTrue(devin2)
        self.assertGreater(devin2[0]["values"]["defensiveness"], 0.0)
        # Prev (Buffy) is present because interaction evidence exists
        self.assertTrue(buffy2)
        self.assertGreater(buffy2[0]["values"]["fatigue"], 0.0)


class PublicStateConformanceTests(unittest.TestCase):
    def test_single_event_does_not_rewire(self):
        # ONE EVENT NEVER CHANGES PUBLIC STATE: EWM caps the jump.
        obs = [observation(1, "feat: huge feature", files=[f"f{i}.gd" for i in range(20)])]
        snapshots = build_public_state(obs)
        head = snapshots[-1]
        for name, state in head["public_states"].items():
            for axis in AXES:
                self.assertLessEqual(state[axis], 0.55, f"{name}.{axis} moved too far from one event")

    def test_aggregation_has_audit_trail(self):
        obs = [observation(1, "feat: a"), observation(2, "fix: repair a")]
        snapshots = build_public_state(obs)
        for snapshot in snapshots:
            self.assertEqual(snapshot["rule_version"], "public_state/v2")
            for name, update in snapshot["updates"].items():
                self.assertIn("previous", update)
                self.assertIn("deltas", update)
                self.assertIn("new", update)
                self.assertIn("rule", update)
                self.assertIn("evidence", update)
                self.assertEqual(update["evidence"], [snapshot["observation_seq"]])
                for axis in AXES:
                    before = update["previous"][axis]
                    after = update["new"][axis]
                    self.assertAlmostEqual(before + update["deltas"][axis], after, places=5)

    def test_public_state_deterministic(self):
        obs = [observation(1, "feat: a"), observation(2, "merge: branch")]
        self.assertEqual(build_public_state(obs), build_public_state(obs))


class SpotlightConformanceTests(unittest.TestCase):
    def test_bounds_never_violated(self):
        obs = [observation(i, "feat: x", narrator="Buffy") for i in range(1, 40)]
        for seq in range(1, 40):
            result = select_narrator(
                composite=obs[seq - 1]["composite"],
                history=[{"seq": s, "narrator": "Buffy"} for s in range(1, seq)],
                current_seq=seq,
                public_state={"Buffy": {"visibility": 1.0, "hype": 1.0, "reputation": 1.0, "controversy": 1.0}},
            )
            self.assertNotIn("error", result)
            for candidate in result["candidates"]:
                self.assertGreaterEqual(candidate["balance_modifier"], BALANCE_LOWER - 1e-9)
                self.assertLessEqual(candidate["balance_modifier"], BALANCE_UPPER + 1e-9)
                self.assertGreaterEqual(candidate["social_modifier"], SOCIAL_LOWER - 1e-9)
                self.assertLessEqual(candidate["social_modifier"], SOCIAL_UPPER + 1e-9)
                self.assertGreaterEqual(candidate["final_weight"], MIN_WEIGHT - 1e-9)
                self.assertLessEqual(candidate["final_weight"], MAX_WEIGHT + 1e-9)

    def test_deterministic_selection(self):
        history = [{"seq": s, "narrator": "Buffy"} for s in range(1, 10)]
        first = select_narrator("c10j3n5a2p7", history, 10)
        second = select_narrator("c10j3n5a2p7", history, 10)
        self.assertEqual(first, second)
        self.assertEqual(first["selected"], second["selected"])

    def test_selection_audit_breakdown(self):
        result = select_narrator("c10j3n5a2p7", [{"seq": 1, "narrator": "Buffy"}], 10)
        audit = result["audit"]
        self.assertIn("selection", audit)
        self.assertIn("breakdown", audit["selection"])
        selected = result["selected"]
        breakdown = audit["selection"]["breakdown"][selected]
        self.assertIn("balance", breakdown)
        self.assertIn("social", breakdown)
        self.assertIn("recency_factor", breakdown["balance"])
        self.assertIn("opportunity_gap", breakdown["balance"])


class PersonalityConformanceTests(unittest.TestCase):
    def test_all_14_personalities_stable(self):
        self.assertEqual(len(PERSONALITIES), 14)
        self.assertEqual(set(PERSONALITIES.keys()), set(NARRATORS))
        for name, personality in PERSONALITIES.items():
            self.assertEqual(personality.name, name)
            # Static input: every field is a plain value, no dynamic state
            for value in personality.as_dict().values():
                self.assertTrue(isinstance(value, (int, float, str, list, dict)))

    def test_personality_is_frozen_input(self):
        # Frozen dataclass → no runtime mutation possible
        import dataclasses
        self.assertTrue(dataclasses.is_dataclass(PERSONALITIES["Thinker"]))
        with self.assertRaises(dataclasses.FrozenInstanceError):
            PERSONALITIES["Thinker"].ambition = 10


class ExplainabilityConformanceTests(unittest.TestCase):
    def test_relationship_state_has_direct_audit_record(self):
        obs = [observation(1, "disagree: reject x", files=["a.gd"])]
        states = build_relationship_state(obs)
        for item in states:
            self.assertIn("previous_values", item)
            self.assertIn("deltas", item)
            self.assertIn("values", item)
            self.assertIn("evidence_refs", item)
            self.assertIn("rule_version", item)
            for axis in RELATIONSHIP_AXES:
                self.assertAlmostEqual(
                    item["previous_values"][axis] + item["deltas"][axis],
                    item["values"][axis], places=5,
                )

    def test_archive_persists_audit_fields(self):
        chain = {"entries": [
            {"seq": 1, "hash": "aaa", "subject": "feat: add navigation", "summary": "feat: add navigation",
             "narrator": "Buffy", "prev_narrator": "Thinker", "mood": "sachlich", "composite": "c1j1n1a1p1",
             "p_id": 1, "arc": "a1", "data_changes": [{"file": "a.gd", "insertions": 1, "deletions": 0}]},
        ], "repairs": []}
        index = {"commits": {"aaa": {"entities": []}}}
        with TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "chain.json").write_text(canonical_json(chain))
            (root / "index.json").write_text(canonical_json(index))
            snapshot = SourceSnapshot.from_paths(root / "chain.json", root / "index.json")
            archive = Archive(root / "db.sqlite")
            archive.rebuild(snapshot)
            status = archive.status()
            # relationship_state_history now stores previous/deltas/evidence
            self.assertEqual(status["counts"]["relationship_state_history"], 14 * 13)
            self.assertEqual(status["counts"]["beliefs"], 1)
            self.assertEqual(status["counts"]["memory"], 1)
            self.assertEqual(status["counts"]["thread_events"], 1)
            self.assertEqual(status["counts"]["public_state_history"], 1)
            self.assertEqual(status["counts"]["spotlight_selections"], 1)


if __name__ == "__main__":
    unittest.main()