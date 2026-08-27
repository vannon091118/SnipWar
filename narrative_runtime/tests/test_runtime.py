from __future__ import annotations
import json
import tempfile
import unittest
from pathlib import Path
from narrative_runtime.errors import ChainValidationError, HistoryChangedError, ImportAtomicityError
from narrative_runtime.observe import OBSERVATION_FIELDS, SourceSnapshot, build_observations, canonical_json, classify_impulse, event_id, observations_hash
from narrative_runtime.store import Archive
from narrative_runtime.relationships import RELATIONSHIP_AXES, build_relationship_events, build_relationship_state
from narrative_runtime.beliefs import build_beliefs, build_memory
from narrative_runtime.threads import build_threads
from narrative_runtime.perspectives import build_perspectives, build_conflicts
from narrative_runtime.context import ContextUnavailable, build_context
from narrative_runtime.commit_hook import synchronize

def fixture():
    chain = {"entries": [
        {"seq": 1, "hash": "aaa", "subject": "feat: add navigation", "summary": "feat: add navigation", "narrator": "Sage", "mood": "sachlich", "composite": "c1j1n1a1p1", "p_id": 1, "arc": "a1", "data_changes": [{"file": "a.gd", "insertions": 2, "deletions": 0}]},
        {"seq": 2, "hash": "bbb", "subject": "fix: repair navigation", "summary": "fix: repair navigation", "narrator": "Buffy", "prev_narrator": "Sage", "mood": "trocken", "composite": "c2j2n2a1p1", "p_id": 2, "arc": "a1", "data_changes": [{"file": "a.gd", "insertions": 1, "deletions": 1}], "parent_hashes": ["aaa"]},
        {"seq": 3, "hash": "ccc", "subject": "merge: branch", "summary": "merge: branch", "narrator": "Thinker", "prev_narrator": "Buffy", "mood": "warm", "composite": "c3j3n3a1p2", "p_id": 3, "arc": "a1", "data_changes": [{"file": "b.gd", "insertions": 3, "deletions": 0}], "parent_hashes": ["bbb", "other"]}], "repairs": []}
    return chain, {"commits": {"aaa": {"entities": ["F-1"]}, "bbb": {"entities": ["F-1", "C-1"]}, "ccc": {"entities": ["C-1"]}}}

def snap(temp, chain, index):
    p = Path(temp); (p/"chain.json").write_text(canonical_json(chain)); (p/"index.json").write_text(canonical_json(index)); return SourceSnapshot.from_paths(p/"chain.json", p/"index.json")

class RuntimeTests(unittest.TestCase):
    def test_classification_precedence(self): self.assertEqual(classify_impulse("Doku: fix it"), "DOKU")
    def test_observation_purity(self):
        c,i=fixture(); o=build_observations(c,i); self.assertTrue(all(set(x)<=OBSERVATION_FIELDS for x in o)); self.assertEqual(o[1]["prior_file_touchers"]["a.gd"],[1])
    def test_determinism(self):
        c,i=fixture(); o=build_observations(c,i); self.assertEqual(o,build_observations(json.loads(json.dumps(c)),json.loads(json.dumps(i)))); self.assertNotEqual(event_id(1,"aaa"),event_id(1,"changed")); self.assertEqual(observations_hash(o),observations_hash(o))
    def test_gap(self):
        c,i=fixture(); c["entries"][1]["seq"]=4
        with self.assertRaises(ChainValidationError): build_observations(c,i)
    def test_archive(self):
        c,i=fixture()
        with tempfile.TemporaryDirectory() as t:
            s=snap(t,c,i); a=Archive(Path(t)/"db.sqlite"); self.assertEqual(a.import_snapshot(s)["imported"],3); self.assertEqual(a.import_snapshot(s)["imported"],0); self.assertTrue(a.verify(s)); a.rebuild(s); self.assertTrue(a.verify(s))
    def test_amend(self):
        c,i=fixture()
        with tempfile.TemporaryDirectory() as t:
            a=Archive(Path(t)/"db.sqlite"); a.import_snapshot(snap(t,c,i)); c["entries"][1]["hash"]="rewritten"
            with self.assertRaises(HistoryChangedError): a.import_snapshot(snap(t,c,i))
    def test_atomic(self):
        c,i=fixture()
        with tempfile.TemporaryDirectory() as t:
            a=Archive(Path(t)/"db.sqlite")
            with self.assertRaises(ImportAtomicityError): a.import_snapshot(snap(t,c,i),fail_after=2)
            self.assertEqual(a.status()["counts"]["events"],0)
    def test_relationships(self):
        c,i=fixture(); o=build_observations(c,i); e=build_relationship_events(o); self.assertTrue(e); self.assertTrue(all(x["axis"] in RELATIONSHIP_AXES for x in e)); self.assertTrue(build_relationship_state(o))
    def test_beliefs_memory(self):
        c,i=fixture(); o=build_observations(c,i); self.assertTrue(build_beliefs(o)); self.assertTrue(build_memory(o))
    def test_perspectives(self):
        c,i=fixture(); o=build_observations(c,i); p=build_perspectives(o,build_beliefs(o),build_threads(o)); self.assertEqual(build_conflicts(p),[])
    def test_context(self):
        c,i=fixture()
        with tempfile.TemporaryDirectory() as t:
            s=snap(t,c,i); a=Archive(Path(t)/"db.sqlite"); a.rebuild(s); before=(Path(t)/"db.sqlite").read_bytes(); x=build_context(a,s); self.assertEqual(x["facts"]["composite"],"c3j3n3a1p2"); self.assertEqual(before,(Path(t)/"db.sqlite").read_bytes())
    def test_empty_context(self):
        c,i=fixture()
        with tempfile.TemporaryDirectory() as t: self.assertRaises(ContextUnavailable,build_context,Archive(Path(t)/"db.sqlite"),snap(t,c,i))
    def test_incremental(self):
        c,i=fixture()
        with tempfile.TemporaryDirectory() as t:
            s=snap(t,c,i); a=Archive(Path(t)/"a.sqlite"); a.import_snapshot(SourceSnapshot(s.chain,s.index,s.observations[:1],s.output_hash)); a.import_snapshot(s); b=Archive(Path(t)/"b.sqlite"); b.rebuild(s); self.assertEqual(a.meta(),b.meta())
    def test_thread_evidence(self):
        c,i=fixture(); o=build_observations(c,i); self.assertEqual(len(build_threads(o)),3); self.assertTrue(all(x["evidence_refs"] for x in build_threads(o)))
    def test_counter_evidence(self):
        c,i=fixture(); o=build_observations(c,i); first=o[0]; counter=json.loads(json.dumps(first)); counter["seq"]=2; counter["subject"]="rebuttal: change process"; counter["counter_evidence"]={"subject":"change_process","evidence_type":"contradicts"}; b=build_beliefs([first,counter]); self.assertTrue(any(x["evidence_type"]=="contradicts" for x in b)); self.assertLess(b[-1]["confidence"],b[0]["confidence"])
    def test_sync_is_best_effort(self):
        c,i=fixture()
        with tempfile.TemporaryDirectory() as t:
            s=snap(t,c,i); a=Archive(Path(t)/"db.sqlite"); result=synchronize(a,s); self.assertTrue(result["ok"]); self.assertEqual(result["last_seq"],3)

if __name__ == "__main__": unittest.main()
