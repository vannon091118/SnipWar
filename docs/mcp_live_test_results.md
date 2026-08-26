# MCP Live-Test Ergebnisse

Stand: 2026-08-26

## Verdict-Regeln

- `LIVE_GAMEPLAY`: nur sichtbare MCP-Steuerung mit einzelnen Atom-Scripts.
- `MCP_CONTRACT`: Transport, Registry und Tool-Verhalten.
- `AUTONOMY_WORKSPACE`: Workspace-Write-Gate, Journal und Rollback.
- `EDITOR_TOOLING`: Editor-Dock, Editor-Port, Undo/Redo und Schreibfreigabe.
- `FREEZE_E2E`: deterministischer sichtbarer Freeze-/Step-Vertrag.

Kein Contract-, Headless-, Editor- oder Freeze-Ergebnis ist automatisch ein `LIVE_GAMEPLAY`-PASS.

## Lauf `erstes schiff bauen`

- Modus: sichtbare Runtime, MCP-TCP, Zielsuche und Aktionen einzeln.
- Ergebnis: `FAIL / INCOMPLETE`.
- Sichtbar erreicht: Main Menu → neue Welt → Welt-UI mit `WERKSTATT`, `FORSCHUNG`, `PLANETEN`, `TECHNOLOGIE`.
- Sichtbar nicht erreicht: orbitale Werft, Teilekauf, Montage, erstes Schiff.
- Abbruch: `runtime_ux_logs` erhielt `ECONNREFUSED 127.0.0.1:9090` nach dem Start der Welt.
- Vollständiger Trace: `addons/gdscript_mcp/client/playthroughs/first_ship_atomic.trace.json`.
- Ausführliche Übergabe: `addons/gdscript_mcp/PLAYTEST_HANDOFF.md`.

### MCP-Findings

- `MCP-01`: TCP-Liveness brach während des Runs ab. Diagnose-Sicherheit 95%; verbleibende Fehldiagnosewahrscheinlichkeit 5%.
- `MCP-02`: Der frühere Gesamt-Composer und eine Shell-Kette verletzten den Atomvertrag. Sicherheit 99%; Fehldiagnose 1%.
- `MCP-03`: Unscharfe `runtime_ux_find`-Suche nach `MILITÄR` konnte das falsche sichtbare Control auswählen. Sicherheit 95%; Fehldiagnose 5%.
- `MCP-04`: Screenshot meldete blank/uniform, obwohl UX-Scan Controls lieferte. Sicherheit 90%; Fehldiagnose 10%.
- `MCP-05`: Koordinaten-/Viewport-Transformation war sichtbar; Node-Pfad-Klick war robuster. Sicherheit 90%; Fehldiagnose 10%.

### Game-Findings

- `GAME-01`: Werkstatt zeigt `Keine eigene Werft vorhanden — zuerst Orbitale Werft bauen.` Sicherheit 98%; Fehldiagnose 2%.
- `GAME-02`: Forschungs-UI blieb disabled, während read-only State/Log Abschluss meldete. Sicherheit 75%; Fehldiagnose 25%.
- `GAME-03`: Geratene Planetkoordinate selektierte nicht; live gefundener `ClickArea`-Node funktionierte. Sicherheit 90%; Fehldiagnose 10%.
- `GAME-04`: Weg vom Werft-Design zur sichtbaren Werftaktion bleibt unerforscht. Sicherheit 99%; Fehldiagnose 1%.

## Atom-Script-Prüfung

Ausgeführt: `node --check` für jedes Script unter `client/playthroughs/atomic/`.

Ergebnis: `ATOMS_NODE_CHECK=PASS`.

Der Vertrag wird pro Script geprüft: genau ein Aufruf von `runSingle(...)`, keine verketteten MCP-Tools. `atomic_runtime_logs.js` ist funktional nur bei aktivem Listener nutzbar; der Trace belegt den Transportabbruch separat.

## Autonomie- und Rollback-Tests

Diese Tests sind keine sichtbaren Spieleraktionen:

- `mcp_build_check.gd`: **PASS**, alle drei Autonomie-Ressourcen geladen; keine NUL-Parsing-Warnungen.
- `mcp_autonomy_contract_test.gd`: **PASS**, 0 Fehler; Read-/Mutation-Gates und maschinenlesbare Evidenz geprüft.
- `mcp_autonomy_write_gate_test.gd`: **PASS**, 0 Fehler; Schreibsperre, Workspace, Patch, Export, Einzel-Rollback und `rollback_all` geprüft. Der absichtlich ungültige Export erzeugte den erwarteten Parse-Fehler-Log.
- `mcp_workspace_contract_test.gd`: **PASS**, 0 Fehler; Journal, Hashes, Baseline, Einzel-Rollback und `rollback_all` geprüft. Der Kontrollzeichen-Test nutzt kein NUL mehr, sondern `char(1)`.

## Freeze-/Step-Test

`freeze_step` liegt im sichtbaren `mcp_e2e.gd`-Szenario und ist kein `.tres`-Szenario. Ausgeführt mit echtem Renderer: **PASS**, 12 Schritte, 0 Fehler, 40 Frames korrekt gesteppt, danach re-frozen, unfreezed und `game_view`/`PlanetField` bestätigt. Ein erster Lauf blieb einmal im `main_menu`; der isolierte Vergleich `new_game_to_world` war PASS und der direkte Wiederholungslauf `freeze_step` war ebenfalls PASS. Das ist daher als flüchtiger Runner-/Timing-Befund, nicht als reproduzierter Game-Regression, dokumentiert. Godot meldete nur Shutdown-Leak-Warnungen nach erfolgreichem Szenario. Das Ergebnis ist ein `FREEZE_E2E`-PASS und niemals ein Schiffbau-PASS.

## Editor-Tooling

Der Editor-Plugin-Vertrag ist statisch belegt:

- Editor-MCP standardmäßig auf Port `9091`, Runtime auf `9090`.
- `editor_write_enabled` ist standardmäßig `false`.
- Editoraktionen `create_node`, `delete_node`, `set_node_property` und Transaktionen sind Undo/Redo-fähig.
- Der Dock stellt Start/Stop, Transport, Port, Auto-Start, Auto-Restart und Schreibfreigabe bereit.
- Editor-Tooling wird separat vom sichtbaren Runtime-Spiel getestet; ein Editor-PASS beweist keine Gameplay-Funktion.
- `godot --headless --editor --path . --quit` wurde als Startcheck versucht, beendete sich innerhalb von 180 Sekunden nicht und liefert deshalb **UNKNOWN/TIMEOUT**, keinen Editor-PASS und keinen Editor-FAIL. Der nächste Agent muss den Editor-Lifecycle mit einer begrenzten Laufzeit bzw. laufendem Editor-Prozess prüfen.

## Implementierter Performance-/UX-Stand

- `runtime_get_scene_tree` akzeptiert `root_path`, `max_depth` und `max_nodes`; Standard ist ein begrenzter Scope statt des Gesamtbaums.
- `runtime_ux_scan` und `runtime_ux_find` akzeptieren `root_path`, `max_controls` und `max_depth`; die Antwort enthält `truncated`, `nodes_visited` und sichtbare `scroll_containers`.
- `runtime_scroll` und `atomic_runtime_scroll.js` führen genau eine virtuelle Mausrad-Geste aus; Scrollposition und Maximalwerte werden im UI-Scan angezeigt.
- `atomic_session.js` hält TCP und MCP-Handshake persistent, führt aber je JSON-Zeile genau einen MCP-Tool-Call aus; die Antwort enthält `elapsed_ms` zur echten Latenzmessung.
- `runtime_chain_validate` blockiert Composite-Tools, sichtbare GameState-/Goal-Abkürzungen, unbegründete Screenshots, fehlende Args/Tools und zu lange sichtbare Ketten vor `runtime_chain_run`.
- Verifiziert: Build-Check, Atom-Syntax, Main-Menu-Smoke, `new_game_to_world` und wiederholter `freeze_step` sind PASS.

## Neue Performance- und UX-Findings

- `MCP-06`: 30-60 Sekunden pro Aktion sind mit hoher Wahrscheinlichkeit Transport-/Orchestrator-Overhead: neuer Node-Prozess, TCP-Connect und MCP-Handshake pro Atom sowie redundante Find/Scan/Screenshot/Wait/Log-Aufrufe.
- `MCP-07`: Endloses Weiterarbeiten ohne Fortschritt braucht einen No-progress-Circuit-Breaker mit UI-Signatur, Zielstatus und Schrittbudget.
- `MCP-08`: Screenshots werden künftig nur bei Unklarheit verpflichtend: widersprüchliche Live-Signale, niedriger Match-Score, unbekanntes Layout, Scroll-Nachweis oder fehlende sichtbare Evidenz.
- `MCP-09`: Fehlendes Scroll-Wissen ist ein echter Spieler-/MCP-Mismatch. `runtime_scroll` und `atomic_runtime_scroll.js` modellieren jetzt eine einzelne sichtbare Mausrad-Geste.
- `MCP-10`: SceneTree und UI werden über `root_path`, `max_depth`, `max_nodes` bzw. `max_controls` begrenzt; der Gesamtbaum ist kein Standardkontext mehr.
- `MCP-11`: `runtime_chain_validate` prüft nun Atomgrenzen, Toolverfügbarkeit, sichtbare Verbote, Screenshot-Gründe, Args, Postconditions und Segmentlänge vor `runtime_chain_run`.

## Chain-Optionen für Endgame-Testing

1. **Persistente atomare Session:** ein TCP-/Handshake pro Lauf, eine MCP-Aktion pro Eingabezeile; empfohlen für wiederholte lokale Teilstrecken.
2. **Validierte Chain-Segmente:** nur bereits erkundete Abläufe verbinden, maximal 20 sichtbare Schritte, Assertion nach jedem relevanten Übergang, Abbruch bei drei identischen UI-Signaturen.
3. **Headless-/Contract-Chains:** Preflight, Rollback und Systemverträge ohne Spieler-PASS; ideal für CPU-intensive Endgame-Mengenläufe.
4. **Exploratives Live-Spiel:** keine Chain-Automation für unbekannte Panels; der Agent entscheidet nach jedem Scan und kann Screenshot/Scroll gezielt anfordern.

## Full Preflight

Ausgeführt mit echtem Renderer: **34/37 Constraints PASS**, **3 FAIL**, 2039/2041 Assertions PASS. Die Fehler waren `world_planets_and_dispatch` (Planet-Tab/Neighbors fehlen), `camera_and_input` (MapCamera nicht im erwarteten Zentrum) und `pause_and_context` mit einem zuvor freigegebenen Instance-Fehler im Pause-Test. Diese Befunde stammen aus den bestehenden Preflight-Fixtures; die neue Runtime-/Atom-Schicht hatte keine Parserfehler. Zusätzlich gab es bekannte Save-/ConceptIndex-/Shutdown-Warnungen. Sie werden getrennt von den neuen MCP-Performance-Findings behandelt.

## Offene Punkte

- Frischen sichtbaren TCP-Run neu starten und nach jedem einzelnen Atom den Schiffbauweg weiter erkunden.
- Forschungs-UI gegen State-/Log-Abschluss mit erneuten sichtbaren Scans prüfen.
- Exakten Ausbaupfad für `ORBITALE WERFT` bestimmen; keine geratenen Koordinaten oder Funktionsaufrufe.
- Bei jedem Transportabbruch zuerst MCP-Finding schreiben und keine Game-Diagnose ableiten.
