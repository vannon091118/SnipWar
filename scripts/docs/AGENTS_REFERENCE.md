# AGENTS.md — Detailreferenz

Diese Datei enthält Hintergrund- und Spezialverträge. `AGENTS.md` bleibt die verbindliche Kurzfassung; bei Konflikten gilt der konkretere Vertrag in den genannten kanonischen Dokumenten.

## Suche

ConceptIndex ist für Architekturfragen zuständig: Klassen, Domänen, freie Slots, Synonyme und Abhängigkeiten.

```bash
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd fleet
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --class ShipManager
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --domain economy
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --free-slots
```

Global Search ist für Volltext über `.gd`, `.tres`, `.tscn`, `.json`, `.md`, Shader und weitere Repo-Dateien zuständig. Die Ausgabe enthält Treffer, Kontext, verfügbare Klassen und Abhängigkeiten.

```bash
$GODOT_BIN --headless --path . --script res://scripts/global_search.gd "fleet"
$GODOT_BIN --headless --path . --script res://scripts/global_search.gd "assemble_ship" --type gd --context 5
$GODOT_BIN --headless --path . --script res://scripts/global_search.gd "runtime_audio|runtime_animation"
$GODOT_BIN --headless --path . --script res://scripts/global_search.gd "func (_?[a-z_]+)" --regex
```

Bei Tool-Code-Suche muss der Harness-Dateifilter `-g '*.gd'` verwenden; `-t gd` ist dort nicht zuverlässig. Neue `class_name`-Skripte gehören in den passenden ConceptIndex-Eintrag; das Datei-Mapping wird automatisch gescannt.

## Preflight

Die kanonische Suite ist V2:

```bash
$GODOT_BIN --headless --path . --script res://scripts/preflight.gd -x
$GODOT_BIN --headless --path . --script res://scripts/preflight.gd --filter=concept_index -v
$GODOT_BIN --headless --path . --script res://scripts/preflight.gd --scope=.doki/scope.json
$GODOT_BIN --headless --path . --script res://scripts/preflight.gd --list
```

`--scope` ist der einzige autoritative Scoped-Modus. Empty, unknown oder duplicate scope muss fail-closed blockieren. Ohne Manifest läuft der vollständige Lauf. Die derzeitige Suite umfasst 44 Constraints. Der Pre-Commit-Hook verwendet `.doki/scope.json`, falls vorhanden, sonst Full-Preflight.

Wichtige Constraints umfassen `game_state_compatibility`, `concept_index`, `save_game_roundtrip`, `save_game_slots`, `mechanic_coverage`, `mcp_capture_contract`, Narrative-Runtime und Docs-Integrity. Quelltext-Scanner überspringen Kommentarzeilen, damit Beispiele nicht als Code zählen.

## DOKI Interna

DOKI ist ein reines Commit-Gate unter `scripts/doki/`: keine Imports, Autoloads oder Signale zu Spiel, MCP oder Agent-System. Die Schichten zeigen nur nach innen:

```text
core (RNG/Verifier) ← chain (Stores) ← character ← prompt ← orchestration (Flows)
```

Der Composite ist `cNjNaP` mit monotonem `c`, RNG-Feldern `j/n/a/p`. Der RNG ist Djb2 plus maskierte XorShift128-Implementierung mit zehn Warmup-Schritten. Gleicher Chain-Zustand, gleicher Diff und gleicher Impuls ergeben denselben Composite, Narrator und Mood. Die Mood-Auswahl darf den vorherigen Mood nicht wiederholen.

Die 14 Narratoren werden aus `n` gewählt, die Mood-/Struktur-Decodierung aus `j`. DOKI schreibt den technischen Commit nicht selbst als Geschichte; der Agent schreibt nach `prompt.txt` Fließtext in der gezogenen Stimme.

Die zehn Verifier-Checks sind in `scripts/doki/README.md` kanonisch beschrieben. Checks 1–6 sind weich, Checks 7–10 hart; zusätzliche Verifier-Erweiterungen müssen Selfchecks und die README synchron halten. Check 10 beschränkt User-Dateien auf höchstens 30 pro Commit; auto-managed DOKI-Dateien zählen nicht.

## DOKI-Artefakt-Lifecycle

- `prepare`: Diff, Chain-Zustand, Composite, Arc- und Prompt-Kontext bestimmen.
- `finish`: Body zusammensetzen, prüfen, `.commit_msg.txt` erzeugen und die im aktuellen Repository geltende Artifact-Policy einhalten.
- `git commit -F .commit_msg.txt`: Hook führt Preflight und DOKI-Gates aus.
- `finalize`: Chain/Index/Arc-Artefakte nach erfolgreichem Commit aktualisieren; `doki repair` behebt verwaiste verified-Sessions oder unterbrochene Finalisierung.

Bei Änderungen an der Artifact-Policy müssen `scripts/doki/README.md`, `AGENTS.md`, Hook-Verhalten und Selfchecks gemeinsam geprüft werden. Runtime-Fehler dürfen den Commit niemals blockieren.

## MCP Async-Vertrag

`mcp_server.gd` routet anhand des `_async`-Feldes der Tool-Definition. Suspendierende Handler, insbesondere Screenshot-Capture nach `frame_post_draw`, sind `_async=true`, besitzen einen `dispatch_async`-Arm und weisen den synchronen Arm mit `async-only` zurück. Ein neues `await` propagiert durch alle Aufrufer; ein nicht wartender Aufrufer erhält sonst einen `GDScriptFunctionState` statt eines Dictionaries. Verifikation: `mcp_capture_contract` und `scripts/testing/mcp_capture_entry_test.gd`.

## Narrative Runtime

Die verbindliche Spezifikation ist `scripts/doki/NARRATIVE_ENGINE_DESIGN.md`:

- Git-History, `narrative_chain.json`, `change_index.json`, DOKI-Session und Verifier sind die Wahrheit.
- Python/SQLite sind deterministische, löschbare Ableitungen; SQLite ist keine zweite Wahrheit.
- Runtime darf Chain, Index oder DOKI-Dateien nicht schreiben und darf den Commit-Flow nicht blockieren.
- Chain-Anker bestehen aus letzter Seq, Commit-Hash und Entry-Digest. Rewrite derselben Seq muss `HISTORY CHANGED` und Rebuild erzwingen.
- Runtime berechnet Composite, Narrator oder `n/j` nicht neu.
- `python -m narrative_runtime import|rebuild|verify|status` nutzt Exit 0 für Erfolg, 2 für Rebuild, 3 für ungültige Chain und 1 für sonstige Fehler.
- Das NARRATIVE_RUNTIME_GATE prüft stdlib-only, Purity, deterministische IDs, Chain-Lücken, Schreibschutz, Idempotenz und Rebuild-Gleichheit.

## Godot-Spezialfallen

Zusätzlich zu den Kurzregeln in `AGENTS.md`:

- `NavigationWaypoint.configure()` kann vor `_enter_tree()` laufen; keine `@onready`-Abhängigkeit darin.
- `Array.map()` muss vor Zuweisung an typisierte Felder explizit typisiert werden.
- `OS.is_stdin_connected()` existiert in Godot 4.7 nicht; stdin nur über explizites Flag behandeln.
- `StreamPeerTCP.get_data()` liefert ein Fehler-/Daten-Array, kein `PackedByteArray`.
- `RefCounted` besitzt kein `get_node_or_null()`; den Root über den Main Loop ermitteln.
- Nach `free()` nicht unzuverlässig über `get_class()` auf eine Instanz zugreifen.
- Headless-Viewport-Geometrie und `current_scene`-Namen sind keine stabilen UI-Testassertions.
- `McpVisionCapture` muss den Frame-Synchronisationsvertrag exakt einhalten; synchrone Umgehungen sind verboten.

## Weitere Referenzen

- `scripts/doki/README.md` — DOKI-Flow, Composite, Checks, Recovery und Dateien.
- `scripts/doki/NARRATIVE_ENGINE_DESIGN.md` — Narrative-Runtime-Vertrag.
- `docs/FINDINGS.md` — zentrale Befunde.
- `ARCHITECTURE.md`, `DESIGN.md`, `VISION.md` — Spielarchitektur und Design.
- `scripts/testing/SCENARIO_LOADER_SPEC.md` — ScenarioLoader-API.
- `addons/gdscript_mcp/AGENTS.md` — MCP-Testdoktrin.
