#!/usr/bin/env python3
"""
🔬 FORENSICS (AUDIT 3) — immutability_gate.py

Verifies that every chain entry's PROVENANCE fields are byte-stable across the
committed history of narrative_chain.json. For each seq it locates the OLDEST
committed chain version containing that seq and compares it against today's value.

Fields classified as provenance (a mutation is a FAILURE):
    composite, mood, narrator, c, j, n, a, p, arc, p_id
Informational fields (reported but non-fatal by AUDIT-3 §8: `subject` was a benign
migration, `date`/`summary` derivable): date, subject, summary.

READ-ONLY (git + narrative_chain.json). Exit: 0 = all provenance stable, 1 = mutated.

Run: python3 tests/forensics/immutability_gate.py
"""
import json
import subprocess
import sys
from pathlib import Path

PROVENANCE = ["composite", "mood", "narrator", "c", "j", "n", "a", "p", "arc", "p_id"]
INFORMATIONAL = ["date", "subject", "summary"]


def git(root: Path, *args) -> bytes:
    r = subprocess.run(["git"] + list(args), cwd=str(root), capture_output=True)
    if r.returncode != 0:
        raise RuntimeError("git %s failed: %s" % (args, r.stderr.decode("utf-8", "replace")))
    return r.stdout


def repo_root(start: Path) -> Path:
    p = start
    while True:
        if (p / "narrative_chain.json").exists():
            return p
        nxt = p.parent
        if nxt == p:
            raise RuntimeError("narrative_chain.json not found above %s" % start)
        p = nxt


def chain_at(root: Path, sha: str) -> dict:
    raw = git(root, "show", sha + ":narrative_chain.json")
    try:
        d = json.loads(raw.decode("utf-8"))
    except Exception:
        return {}
    return {e["seq"]: e for e in d.get("entries", [])}


def main() -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    root = repo_root(Path(__file__).resolve().parent)
    current = {e["seq"]: e for e in
               json.loads((root / "narrative_chain.json").read_text(encoding="utf-8"))["entries"]}

    log = [sha for sha in git(root, "log", "--format=%H", "--", "narrative_chain.json")
           .decode().split() if sha]
    log.reverse()  # oldest -> newest

    # Load each committed chain exactly once; record the OLDEST (first) commit that
    # already contains each seq. (One git-show per commit touching the file.)
    first_containing: dict = {}
    for sha in log:
        c = chain_at(root, sha)
        for seq in c:
            if seq not in first_containing:
                first_containing[seq] = sha

    print("seq | first-commit | provenance | field diffs")
    failures = 0
    informational_diffs = 0
    pending = []
    for seq in sorted(current):
        created = first_containing.get(seq)
        if created is None:
            pending.append(seq)
            continue
        e = chain_at(root, created)[seq]
        cur = current[seq]
        prov = [f for f in PROVENANCE if e.get(f) != cur.get(f)]
        info = [f for f in INFORMATIONAL if e.get(f) != cur.get(f)]
        if prov:
            failures += 1
            print("%-4d| %-12s | MUTATED      | %s" % (seq, created[:10],
                  "; ".join("%s:%r->%r" % (f, e.get(f), cur.get(f)) for f in prov)))
        elif info:
            informational_diffs += 1
            print("%-4d| %-12s | STABLE       | [info] %s" % (seq, created[:10],
                  "; ".join("%s:%r->%r" % (f, e.get(f), cur.get(f)) for f in info)))
        else:
            print("%-4d| %-12s | STABLE" % (seq, created[:10]))

    n_committed = len([s for s in current if s not in pending])
    committed = [s for s in current if s not in pending]
    monotonic = committed == list(range(1, max(committed) + 1)) if committed else False
    print()
    if pending:
        print("PENDING (working tree only, never committed -> not history, not a mutation):", pending)
    print("checked_committed=%d provenance_stable=%s informational_diffs=%d sequence=%s" % (
        n_committed, "all" if failures == 0 else "FAIL (n=%d)" % failures,
        informational_diffs,
        "monotonic 1..%d" % max(committed) if monotonic else "gaps/holes"))
    status = "IMMUTABLE-OK (core provenance byte-stable across committed chain history)" if failures == 0 \
        else "MUTATION-DETECTED"
    print("VERDICT:", status)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())