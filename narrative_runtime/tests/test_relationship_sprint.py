from __future__ import annotations

import unittest

from narrative_runtime.observe import canonical_json
from narrative_runtime.relationships import (
    NARRATORS,
    RELATIONSHIP_AXES,
    build_relationship_effects,
    build_relationship_state,
    classify_events,
)


def observation(seq: int, subject: str, narrator: str = "Buffy", previous: str = "Thinker", files: list[str] | None = None) -> dict:
    return {
        "seq": seq,
        "subject": subject,
        "summary": subject,
        "narrator": narrator,
        "prev_narrator": previous,
        "files": files or ["a.gd"],
        "entities": [],
        "subject_term_flags": {"repair": subject.lower().startswith("fix"), "test": False, "merge": False},
        "relationship_facts": {
            "explicit_admission": "my mistake" in subject.lower(),
            "explicit_disagreement": "disagree" in subject.lower(),
            "explicit_revert": "revert" in subject.lower(),
            "stance": "minimal" if "minimal" in subject.lower() else None,
        },
        "is_merge": False,
        "mood": "sachlich",
    }


class RelationshipSprintTests(unittest.TestCase):
    def test_structural_matrix(self):
        states = build_relationship_state([observation(1, "feat: start")])
        pairs = {(x["source"], x["target"]) for x in states}
        self.assertEqual(len(pairs), 14 * 13)
        self.assertTrue(all(source != target for source, target in pairs))
        self.assertTrue(all(set(x["values"]) == set(RELATIONSHIP_AXES) for x in states))
        self.assertEqual(set(NARRATORS), {source for source, _ in pairs} | {target for _, target in pairs})

    def test_fix_is_not_regression_or_admission(self):
        event = classify_events([observation(1, "fix: repair broken references")])[0]
        self.assertEqual(event["classification"], "NONE")
        effects = build_relationship_effects([observation(1, "fix: repair broken references")])
        self.assertTrue(effects)
        self.assertNotIn("irritation", {x["axis"] for x in effects})

    def test_negative_axes_and_admission(self):
        obs = [observation(1, "feat: initial"), observation(2, "fix: my mistake, I broke it")]
        effects = build_relationship_effects(obs)
        by_axis = {x["axis"]: x["delta"] for x in effects if x["observation_seq"] == 2}
        self.assertEqual(by_axis["trust"], 0.02)
        self.assertEqual(by_axis["resentment"], -0.02)

    def test_explicit_disagreement_only(self):
        stance = classify_events([observation(1, "proposal: minimal docs")])[0]
        self.assertEqual(stance["classification"], "STANCE_DIFFERENCE")
        no_interaction = classify_events([observation(1, "proposal: minimal docs", files=["a.gd"]), observation(2, "disagree: reject detailed docs", narrator="Devin", previous="Ghost", files=["b.gd"])])
        self.assertEqual(no_interaction[1]["classification"], "NONE")
        disagreement = classify_events([observation(1, "proposal: minimal docs", files=["a.gd"]), observation(2, "disagree: reject detailed docs", narrator="Devin", previous="Ghost", files=["a.gd"])])[-1]
        self.assertEqual(disagreement["classification"], "DISAGREEMENT")
        axes = {x["axis"] for x in build_relationship_effects([observation(1, "proposal: minimal docs", files=["a.gd"]), observation(2, "disagree: reject detailed docs", narrator="Devin", previous="Ghost", files=["a.gd"])]) if x["observation_seq"] == 2}
        self.assertEqual(axes, {"defensiveness", "resentment"})

    def test_unrelated_revert_does_not_upgrade_prior_event(self):
        first = observation(1, "fix: repair a", files=["a.gd"])
        later = observation(2, "revert: restore b", files=["b.gd"])
        events = classify_events([first, later])
        self.assertNotIn("upgraded_classification", events[0])

    def test_later_revert_upgrades_prior_repair_without_mutating_observation(self):
        first = observation(1, "feat: add docs")
        second = observation(2, "revert: restore docs broken by prior change")
        before = canonical_json(first)
        events = classify_events([first, second])
        self.assertEqual(canonical_json(first), before)
        self.assertEqual(events[0]["classification"], "NONE")
        self.assertEqual(events[1]["classification"], "REGRESSION_CONFIRMED")
        self.assertTrue(events[1]["evidence_refs"])

    def test_effects_have_separate_event_and_effect_ids(self):
        effects = build_relationship_effects([observation(1, "disagree: reject this")])
        self.assertTrue(effects)
        self.assertTrue(all(x["effect_id"] != x["event_id"] for x in effects))
        self.assertEqual(len({x["event_id"] for x in effects}), 1)
        self.assertTrue(all(x["evidence_refs"] for x in effects))

    def test_empty_archive_verifies(self):
        from pathlib import Path
        from tempfile import TemporaryDirectory
        from narrative_runtime.observe import SourceSnapshot
        from narrative_runtime.store import Archive
        with TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "chain.json").write_text(canonical_json({"entries": [], "repairs": []}))
            (root / "index.json").write_text(canonical_json({"commits": {}}))
            snapshot = SourceSnapshot.from_paths(root / "chain.json", root / "index.json")
            archive = Archive(root / "db.sqlite")
            archive.rebuild(snapshot)
            self.assertTrue(archive.verify(snapshot))

    def test_batch_independence(self):
        all_obs = [observation(1, "feat: one"), observation(2, "fix: repair one"), observation(3, "disagree: reject two")]
        full = build_relationship_state(all_obs)
        split = build_relationship_state(all_obs[:1] + all_obs[1:])
        self.assertEqual(full, split)


if __name__ == "__main__":
    unittest.main()
