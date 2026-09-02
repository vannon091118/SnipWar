# DOKI — gepinntes, entkoppeltes Home

DOKI ist seit der Entkopplung **kein Bestandteil dieses Repos mehr**, sondern ein
eigenes, gepinntes Mini-Projekt auf dem Desktop:

```
C:/Users/Vannon/Desktop/doki/
  VERSION            ← Pinn-Version (aktuell: 1.0.0)
  project.godot      ← eigenes Godot-Projekt (Kontextfreiheit: kein SnipWar-Code)
  doki/              ← komplette Engine (CLI, Flows, Chain, Character, Prompt, …)
  narrative_runtime/ ← Python-Runtime (Gate-CLI, stdlib-only, Package-Kontext)
  bin/doki(.cmd)     ← Runner (Windows + Git-Bash/macOS/Linux)
  README.md          ← Engine-Doku des Homes
  NARRATIVE_ENGINE_DESIGN.md
```

Das Home ist ein **eigenes git-Repo** (`git init` + gepinnt, s.u.) und damit
ohne SnipWar-Kontext fixierbar, reviewbar und versionierbar. Das Spiel-Repo
behält nur den **per-Repo-Narrative-State**:

| Artefakt | Ort | Zweck |
|---|---|---|
| `narrative_chain.json` | `.doki/` | Git-Wahrheit der Erzählkette |
| `change_index.json` | `.doki/` | Änderungs-Index je Commit |
| `arcs.json` | `.doki/` | Arc-Definitionen (werden beim Finish gepflegt) |
| `CHANGELOG.md` | Root | kompakter Änderungsverlauf |

## Workflow (im Spiel-Repo, aus dem Root)

```bash
git add <konkrete-dateien>
bash C:/Users/Vannon/Desktop/doki/bin/doki prepare "<impuls>"
# .doki/narrator_body.md als Fließtext in der gezogenen Rolle schreiben
bash C:/Users/Vannon/Desktop/doki/bin/doki finish --body-file .doki/narrator_body.md
git commit -F .commit_msg.txt
```

- Der Runner startet Godot mit `--path C:/Users/Vannon/Desktop/doki` und übergibt
  das Ziel-Repo (CWD) als Arbeitsverzeichnis. Das Home schreibt NIE ins Home,
  sondern in das Repo, in dem `prepare`/`finish` aufgerufen werden.
- `finish` staged `.doki/change_index.json` und `CHANGELOG.md`; die Chain wird
  aus der Git-Historie fortgeschrieben (uneingeschränkte Kette, kein Reset).
- **Kein Hook-Gate mehr:** Die Hooks (`.githooks/`) laufen ohne DOKI
  (guard + AgentGate + Verify-Treiber). Der DOKI-Gate ist in den Home-Flow
  gewandert: `doki selfcheck` (111 Checks) und `doki gate` laufen im Home gegen
  das Ziel-Repo.

## Versions-Pinning

- `VERSION` im Home dokumentiert den Stand; Änderungen am Home sind eigene
  Commits im Home-Repo (Branch `main`, Pushes automatisiert via SnipWar-Pipeline
  soweit eingerichtet).
- Ein Upgrade = Commit im Home-Repo + `VERSION`-Bump; das Spiel-Repo referenziert
  das Home nur als Pfad, es pinnt keine Dateien.
- Das Home ist kontextfrei: es importiert weder Spiel-Skripte noch `GameState`,
  MCP oder Scenes. Die einzige Brücke sind die per-Repo-Artefakte unter `.doki/`.

## Verifikation des Homes

```bash
export GODOT_BIN="C:/Users/Vannon/Desktop/godu/Godot_v4.7.2-stable_win64_console.exe"
cd C:/Users/Vannon/Desktop/doki
"$GODOT_BIN" --headless --path . --script res://doki/doki_selfcheck.gd   # 111 Checks
"$GODOT_BIN" --headless --path . --script res://doki/doki.gd -- status   # Chain-Lesung
cd C:/Users/Vannon/Documents/snippet-empire/snip-war
python -c "import sys; sys.path.insert(0, r'C:/Users/Vannon/Desktop/doki'); from narrative_runtime.gate_cli import main; SystemExit(main())" --root .
```

## Warum entkoppelt?

- Ohne SnipWar-Kontext als eigener Ordner fixierbar (Desktop, außerhalb des
  Projekts, eigenes git-Repo, eigener VERSION-Pin).
- Das Spiel-Repo verliert die DOKI-Abhängigkeit in Hooks, Preflight und
  Compile-Gate: `scripts/doki/**` und `.doki/narrative_runtime/**` sind entfernt;
  der Preflight kennt keinen `doki`-Contract mehr (44 Constraints).
- Die Narrative-State-Dateien bleiben im Spiel-Repo und werden weiterhin von
  guard (AUTO-Maske), preflight-Scope (`preflight`-Contract) und den
  Chain-Tests (`chain_validate_entry_test`) abgedeckt.