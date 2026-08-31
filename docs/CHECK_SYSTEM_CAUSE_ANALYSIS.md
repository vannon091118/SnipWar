# CAUSE ANALYSIS — Schwere Inkonsistenzen im Check-System

> **Erstellt:** 2026-08-31 · **Scope:** check.gd, pre-commit Hook, constraint_agent_activity.gd, scope.py, test_all.gd

---

## 🔴 S1: Zwei autoritative Einstiege, die divergieren

### Symptom
`check.gd` wird in `AGENTS.md` als Unified Entry dokumentiert (`scripts/check.gd -x`), ist aber **nirgends als echter Einstieg verdrahtet** — weder im pre-commit-Hook noch als Subprozess.

### Tatsächlicher Gate
Der pre-commit-Hook (`/.githooks/pre-commit`) läuft:
```
DOKI prepare → DOKI gate → compile_gate.gd → preflight.gd -x
```
`check.gd` mit Tests läuft nur manuell. Der Hook führt **keinerlei Entry-Tests** aus.

### Wurzel
`check.gd` wurde als "Unified Check" konzipiert, aber nie in den Hook integriert. Der Hook wurde separat vom Branch-Commit `740bc82` geschrieben und nutzt die alte Sequenz. Zwei Gate-Pfade existieren parallel:
1. **Hook-Pfad:** prepare → gate → compile_gate → preflight (keine Tests)
2. **Manueller Pfad:** check.gd (compile + preflight + tests, scope-gefiltert)

### Folge
Ein Commit gilt als grün, obwohl `*_test.gd`-Dateien nie validiert werden. `check.gd` mit Tests läuft nur manuell.

---

## 🔴 S2: AgentGate-Constraint liest den falschen Registry-Pfad

### Symptom
`constraint_agent_activity.gd:_verify_scope_matches_staged` liest:
```
$(git rev-parse --show-toplevel)/.agent-activity/agents/%s.files
```

Aber `agent_activity.sh:state_dir()` liefert standardmäßig:
```
.git/agent-activity/agents/   (über git-common-dir = .git)
```

### Beweis
- `state_dir()` (Zeile 18-22): nutzt `git rev-parse --git-common-dir` → `.git`
- In diesem Repo existiert `.git/agent-activity/agents/` (geprüft)
- `./.agent-activity/agents/` existiert **nicht**
- Constraint findet keine Dateien → alle staged Files gelten als "uncovered" → False-FAIL

### Wurzel
Der Constraint dupliziert die Coverage-Logik von `run_gate()` statt sie zu nutzen — mit divergentem Pfad. Doppelte Wahrheit.

---

## 🔴 S3: Contract/Constraint-Mapping der Python-Referenz ist veraltet

### Symptom
Godot `constraint_scanner.gd`, Contract `preflight`:
```
[agent_activity, concept_index, global_search, mechanic_coverage, dead_code, mcp_capture_contract]
```

Python `scope.py`, Contract `preflight`:
```
[concept_index, global_search, mechanic_coverage, dead_code, mcp_capture_contract]
```
→ `agent_activity` fehlt in Python.

### Weitere Abweichungen
`_PATH_CONTRACTS` weicht ebenfalls ab. Godot ist deutlich umfangreicher:
- `*.uid` → preflight (Python: fehlt)
- `.gitignore` → docs, preflight (Python: fehlt)
- `scripts/objects/planets/**` → world, economy, navigation (Python: fehlt)
- `scripts/state/event_bus.gd` → history (Python: fehlt)
- `scripts/history/**` → history (Python: hat es)
- `scripts/config/asset_library.gd` → docs, ui_flow (Python: fehlt)
- `resources/config/**` → economy, ships, docs (Python: fehlt)
- `.doki/narrative_chain.json` → doki (Python: nur `narrative_chain.json`)

### Folge
Python-Fallback und Godot-Scope lösen denselben Pfad unterschiedlich auf.

---

## 🔴 S4: Test-Selektor von check.gd ≠ test_all.gd

### Symptom
`check.gd` matcht per hartcodierter `contract_to_test_prefix`-Map:
```
doki → chain, combat → combat, economy → e, ...
```

`test_all.gd` matcht per Substring im Pfad.

### Beispiel
`narrative_runtime_gate_test.gd` wird bei Scope `doki` von `check.gd` **nie** selektiert (Präfix `chain` passt nicht), während `test_all.gd` sie läuft.

### Wurzel
`check.gd` hat eine eigene Test-Selektions-Logik erfunden, die nicht mit `test_all.gd`'s Substring-Matching übereinstimmt.

---

## 🟡 M1: Severity vs. Scope

### Symptom
`classify_staged` (python/scoped/full) → Hook nutzt Severity.
`check.gd` nutzt ChangeImpactResolver-Scope mit `--filter=`.
Zwei unterschiedliche Selektionen für "was wird geprüft".

### Folge
Code-Änderungen laufen im Hook immer als Full-Preflight (kein Scope-Filter), während `check.gd` scope-gefiltert läuft.

---

## 🟡 M2: Marker-Vergleich statt Exit-Code

### Symptom
`check.gd` prüft `exit==0` und `text.contains("RESULT: PASSED")`.
Preflight v2 gibt `RESULT: PASSED` aus — matcht.
Aber Godot-Constraints, die nach PASS dennoch `[FAIL]` loggen, wären über den Marker allein False-Green.

### Folge
`test_all.gd` handhabt das korrekt (Exit-Code = Wahrheit); `check.gd`-Preflight-Phase nicht.

---

## 🟡 M3: Python-Fallback ≠ volle Gate-Abdeckung

### Symptom
`gate_cli.py` validiert nur die narrative Chain; kein AgentGate/Compile/Tests.
Als Fallback dokumentiert, aber nicht in den Hook verdrahtet.
Hook bricht ohne `GODOT_BIN` hart ab.
