# MCP Live Playtest Handoff

Status: 2026-08-26 · **Session-Handoff (historisch)** · Goal: `erstes schiff bauen`

> **Status-Update 2026-08-27:** MCP-06 (30–60 s/Aktion) ist durch den
> persistenten Standard-Transport `mcp_file_driver.js` (ein Prozess + ein
> Handshake, eine Zeile = genau ein Tool-Call, 4–16 ms) behoben; MCP-07 ist
> durch die entkoppelte `visual_evidence`-Analyse adressiert. Der Spieler-
> Vertrag (Atom-Registry unten) bleibt unverändert verbindlich. Die
> Tool-Zahlen sind in `MCP_INDEX.md` aktualisiert (143 Domain + 6 Host).

## Session-Profile (verbindlich, seit v4.1 erzwungen)

Die Spieler-Verträge unten werden vom Server durchgesetzt (`mcp_contract_gate.gd`):

- **Runtime-Sessions starten standardmäßig als `player`** — Goal-Player, Chains,
  Eval, Freeze/Step, `runtime_ux_click`, `game_state_restore`, E2E-Szenarien und
  Autonomy-Writes sind gesperrt; Verstöße erscheinen als `contract_violations`
  in `runtime_mcp_status` und als Lifecycle-Event.
- `--mcp-profile=qa` (Debug/QA) oder `--mcp-profile=dev` (Reparatur) schalten
  die Orchestrierungs-/Debug-Tools frei. Der Editor-Dock schreibt das Profil
  als „Play-Goal“ nach `user://gdscript_mcp_profile.cfg` — wirkt beim nächsten
  Runtime-Boot.
- `editor_run_project(with_mcp=true)` startet das Spiel aus dem Editor mit
  Runtime-MCP (9090): der Agent wechselt damit per Tool-Call Edit ↔ Ingame.

## Maus-Regel: sanfter Cursor-Travel, kein Teleport

Seit v4.1 ist die virtuelle Maus standardmäßig sichtbar-bewegt: `runtime_mouse_move`
und `runtime_click` interpolieren den Cursor über mehrere Frames (`smooth=true`,
`duration_ms`), statt zu springen. Agenten, die den Cursor „teleportieren“,
verhalten sich damit wie echte Spieler und Hover-Effekte feuern korrekt.

## Verbinderlicher Spieler-Vertrag

Ein sichtbarer Playtest wird wie ein Spieler ausgefuehrt. Der Agent entscheidet den naechsten Zug erst nach der letzten Live-Beobachtung.

1. MCP-TCP-Handshake ueber `127.0.0.1:9090`.
2. Live-UI lesen: `runtime_ux_scan` oder gezielte `runtime_ux_find`, standardmäßig mit begrenztem `root_path`, `max_controls`, `max_depth`.
3. Ein Ziel bestaetigen, ohne es zu klicken.
4. Virtuelle Maus mit einem eigenen Atom bewegen: `runtime_mouse_move`.
5. Separat beobachten, falls Hover fuer die Diagnose relevant ist.
6. Genau einen Klick mit einem eigenen Atom senden: `runtime_click`.
7. Separat warten, sofern ein UI-Uebergang erwartet wird.
8. Separat scannen; Screenshot nur bei Unklarheit, Widerspruch, Scroll-Nachweis oder fehlender sichtbaren Evidenz.
9. Erst danach den naechsten Spielerzug bestimmen.

Ein Ingame-Script darf genau einen MCP-Tool-Call ausfuehren. Es darf keine Zielsuche, Mausbewegung, Klick, Wartezeit, Folgeaktion oder GameState-Mutation verstecken. `runtime_game_state_summary` ist in diesem Vertrag nur eine read-only Beobachtung und kein Steuerungsweg. `atomic_session.js` darf den Transport persistent halten, aber jede JSON-Zeile bleibt genau ein MCP-Call.

Nicht erlaubt fuer sichtbare Spielerlaeufe:

- direkte GameState-Aufrufe oder Resource-/Domain-Mutationen
- `runtime_goal_sequence`, `runtime_goal_play` oder `runtime_chain_run` als Live-Spieler-Ersatz
- ein Runner, der mehrere Atome in einem Aufruf, einer Shell-Kette oder einem vorgeplanten Gesamtplan ausfuehrt
- `runtime_ux_click`, weil Find+Click fuer diesen Vertrag zwei Aktionen in einem Tool verbirgt (im player-Profil serverseitig gesperrt)
- Freeze/Step, Goal-Player, Chains und E2E-Szenarien (im player-Profil serverseitig gesperrt)
- Forschung, Werftbau, Teilekauf oder Schiffmontage ueber Funktions-Calls

### `runtime_ux_click` Verdict-Semantik (MCP-007)

`runtime_ux_click` liefert bei Erfolg **kein** `SOLVED`-Verdict, sondern `TO_CHECK`:

| Verdict | Bedeutung |
|---------|-----------|
| `MCP_ISSUE` | Klick dispatched aber SceneTree-Signatur unverändert — Input landete nicht |
| `INCONCLUSIVE` | Live-State geaendert aber Screenshot-Capture fehlgeschlagen |
| `TO_CHECK` | **Live-State UND Screenshot bestaetigen Aenderung** — Agent muss manuell bestaetigen, dass das gewuenschte UI-Ergebnis eingetreten ist (z.B. Panel geoeffnet, Button disabled, Text geandert) |

**Grund:** Nur der Agent kennt die *Intent* der Aktion (\"Forschung starten\" vs \"Panel schliessen\"). Der Server kann nur technisch bestaetigen, dass sich der Zustand geandert hat, nicht ob die Aenderung der *Intent* entspricht.

**Workflow:** Nach `runtime_ux_click` → `verdict: "TO_CHECK"` → Agent prüft `receipt.after_live` / `receipt.artifact` → bei Bestätigung nächsten Zug planen.

Autonomie-Repair, Headless-Vertragstests und Editor-Operationen sind eigene Modi. Sie duerfen nicht als sichtbares Spielergebnis gemeldet werden.

## Atom-Registry

Alle Scripts liegen unter `client/playthroughs/atomic/`. Das gemeinsame Transportmodul `atomic_client.js` darf nur genau einen MCP-Call pro Prozess herstellen.

| Script | Genau ein Call | Zweck | Status |
|---|---|---|---|
| `atomic_runtime_scan.js` | `runtime_ux_scan` | sichtbare UI beobachten | PASS im Run |
| `atomic_runtime_find.js` | `runtime_ux_find` | ein Ziel beobachten | PASS, aber Text-Matching kann falsch sein |
| `atomic_runtime_mouse_move.js` | `runtime_mouse_move` | virtuelle Maus einmal bewegen | PASS |
| `atomic_runtime_click.js` | `runtime_click` | eine Press/Release-Geste | PASS |
| `atomic_runtime_wait.js` | `runtime_wait_ms` | einmal warten | PASS |
| `atomic_runtime_screenshot.js` | `runtime_screenshot` | ein sichtbares Frame-Artefakt | PASS, Qualitaetsbefund widerspruechlich |
| `atomic_runtime_scene_tree.js` | `runtime_get_scene_tree` | begrenzten Live-Szenenbaum lesen | PASS |
| `atomic_runtime_scroll.js` | `runtime_scroll` | eine sichtbare Scroll-Geste | PASS nach Build-/Renderer-Integration |
| `atomic_session.js` | persistenter MCP-Transport | eine Tool-Aktion pro Eingabezeile ohne neuen Handshake | PASS Syntax; Laufzeit-Latenz noch zu messen |
| `atomic_runtime_find_node.js` | `runtime_find_node` | einen Node beobachten | PASS |
| `atomic_game_state_summary.js` | `game_state_summary` | read-only Zustand beobachten | PASS, niemals Steuerung |
| `atomic_runtime_logs.js` | `runtime_ux_logs` | ein Logdelta lesen | FAIL bei MCP-Abbruch |

Der fruehere Gesamt-Composer `first_ship_atomic.js` wurde aus dem ausfuehrbaren Bestand entfernt, weil er Zielsuche, Hover, Screenshot, Klick, Wait, Scan, State- und Log-Lesen in einer vorgeplanten Funktion verbunden hat. Der Trace bleibt als historische Evidenz erhalten. Ein kuenftiger manueller Lauf startet jeweils nur ein einzelnes Atom als separaten Prozess.

## Ausfuehrungsprotokoll: abgebrochener Run

Trace: `client/playthroughs/first_ship_atomic.trace.json`

| Schritt | Live-Beobachtung / Aktion | Ergebnis |
|---|---|---|
| 0-2 | Main Menu gescannt und read-only Baseline gelesen | `NEUES SPIEL` aktiv; 0 Schiffe; Startressourcen sichtbar |
| 3-8 | `NEUES SPIEL`: find, Mausbewegung, Hover-Scan, Screenshot, ein Klick, Wait | Klick angenommen; Wechsel nach `game_view` |
| 9-10 | Welt gescannt und State beobachtet | `PLANETEN`, `TECHNOLOGIE`, `WERKSTATT`, `FORSCHUNG`; Heimatwelt `p0`; 0 Schiffe |
| 11 | Logdelta nach dem Start gelesen | `ECONNREFUSED 127.0.0.1:9090`; Lauf abgebrochen |

Der Run hat **kein erstes Schiff gebaut**. Es gibt keinen PASS fuer das Goal.

Weitere live belegte Beobachtungen aus der anschliessenden manuellen MCP-Erkundung:

- `WERKSTATT` oeffnet sichtbar ein Panel mit `Keine eigene Werft vorhanden — zuerst Orbitale Werft bauen.`
- `FORSCHUNG` zeigte `Orbitales Werft-Design` sichtbar und zunaechst aktiviert. Ein einzelner MCP-Klick setzte den sichtbaren Button auf disabled.
- Nach Wartezeit blieb der Button disabled, waehrend eine read-only State-/Log-Beobachtung `shipyard_construction` als abgeschlossen meldete.
- Nach erneutem Oeffnen zeigte die Werkstatt weiterhin den Gate-Text zur fehlenden orbitalen Werft.
- Ein Klick auf die ungefaehre Planetkoordinate `(160,90)` selektierte keinen Planeten. Der live beobachtete SceneTree-Node `Player Homeworld/ClickArea` konnte dagegen per MCP-Node-Pfad geklickt werden; danach waren `PLAYER HOMEWORLD`, 6 Einheiten und 3 Bauplaetze sichtbar.
- Eine unscharfe Suche nach `MILITAR` traf zuerst ein Missions-Optionsfeld statt der geschlossenen Ausbaukategorie. Der exakte sichtbare Text `▸ MILITAR` muss vor einem Klick bestaetigt werden.

## Neue Findings: MCP-Mismatch und Geschwindigkeit

| ID | Befund | Wahrscheinliche Ursache | Diagnose-Sicherheit | Wahrscheinlichkeit Diagnose falsch |
|---|---|---|---:|---:|
| MCP-06 | Eine einzelne Aktion dauert beobachtet 30-60 Sekunden | Atom-Prozess startet Node neu, TCP-Verbindung neu, MCP-Handshake `initialize` + `initialized` pro Aktion; danach entstehen zusätzliche Scan-/Wait-/Log-Aufrufe | 0.92 | 0.08 |
| MCP-07 | CPU/Agent arbeitet weiter, obwohl kein sichtbarer Fortschritt zum Ziel entsteht | Kein globaler No-progress-Circuit-Breaker; Goal-/Chain-Pfade können wiederholt dieselben Beobachtungen oder disabled Ziele anfordern | 0.90 | 0.10 |
| MCP-08 | Screenshots werden als Standardbeobachtung statt nur bei Unklarheit eingesetzt | Historischer Ablauf enthält Screenshot vor jedem Klick; `runtime_ux_click` koppelt Beobachtung und Screenshot | 0.96 | 0.04 |
| MCP-09 | Der Agent erkennt nicht zuverlässig, dass Panels scrollbar sind | Kein dediziertes Scroll-Atom und kein sichtbarer ScrollContainer-Hinweis im kompakten UI-Kontext | 0.95 | 0.05 |
| MCP-10 | SceneTree-/UI-Kontext ist zu groß | Vollständige Baum-/Control-Listen werden angefordert; Scope, Tiefen- und Node-Limits waren nicht verbindlich | 0.97 | 0.03 |
| MCP-11 | Wiederholbare Teilstrecken werden nicht effizient verkettet | Es existiert ein Chain Controller, aber die alte Validierung prüfte weder Atomgrenzen noch Screenshot-Gründe, Payload-Limits, No-progress noch visible-mode Verbote | 0.91 | 0.09 |

### Geschwindigkeitsregeln ohne Qualitätsverlust

- **Normalfall:** Live-`runtime_ux_scan` mit begrenztem Scope, danach direkt eine atomare Aktion. Kein Screenshot, wenn Labels, `disabled`, Rect und Node-Pfad eindeutig sind.
- **Screenshot nur bei Unklarheit:** aufnehmen bei widersprüchlichem Live-/State-Signal, niedrigem Match-Score, unbekanntem Layout, nach Scroll-Gesten wenn das Ziel nicht auftaucht, oder wenn der sichtbare Zustand das einzige Beweismittel ist.
- **Persistenter Transport:** `atomic_session.js` hält einen MCP-TCP-Socket und den Handshake offen. Jede Eingabezeile führt trotzdem genau einen MCP-Tool-Call aus. Das reduziert nur Prozess-/Handshake-Overhead.
- **Beobachtungs-Caching:** innerhalb desselben Frames bzw. über `runtime_ux_watch_start`/`runtime_ux_snapshot` keine identische Vollanalyse wiederholen.
- **No-progress:** Nach spätestens 3 gleichen UI-Signaturen, 2 gleichen disabled-Zielen oder 2 fehlgeschlagenen Transportversuchen stoppen und als `MCP_ISSUE`, `GAME_ISSUE` oder `UNKNOWN` klassifizieren. Kein Endloslauf.


| ID | Befund | Evidenz | Diagnose-Sicherheit | Wahrscheinlichkeit Diagnose falsch |
|---|---|---|---:|---:|
| MCP-01 | MCP-Verbindung ist waehrend des laufenden Runs abgerissen | `runtime_ux_logs`: `ECONNREFUSED` nach erfolgreichem Handshake und mehreren Calls | 0.95 | 0.05 |
| MCP-02 | Der Gesamt-Runner verletzt die Bedienungsgrenze, wenn er fuer Live-Playtesting gestartet wird | Trace-Composer ruft mehrere Atom-Prozesse in einer vorgeplanten Funktion auf; ein Terminal-Aufruf wurde zudem als Kette ausgefuehrt | 0.99 | 0.01 |
| MCP-03 | Zielsuche kann semantisch falsches sichtbares Element liefern | `MILITAR` traf Missions-Option statt Ausbaukategorie | 0.95 | 0.05 |
| MCP-04 | Screenshot-Metadaten koennen der Live-UI widersprechen | Screenshot meldete `quality: blank`, `unique_colors: 1`, waehrend der UI-Scan Controls lieferte | 0.90 | 0.10 |
| MCP-05 | Koordinaten und Klickantwort zeigen Viewport-/Screen-Transformation | Mausposition `(480,251)`, Klickantwort `(640,334)`, Scale `1.333...`; Node-Pfad-Klick war robuster | 0.90 | 0.10 |

MCP-01 muss vor einem neuen Run durch einen frischen Handshake und einen einzelnen Status-/Scan-Call geklaert werden. Ein Tool-Ergebnis darf bei Verbindungsabbruch nicht als Game-Failure interpretiert werden.

## Neue Findings: Game-Mismatch / Spielerwissen

| ID | Befund | Evidenz | Diagnose-Sicherheit | Wahrscheinlichkeit Diagnose falsch |
|---|---|---|---:|---:|
| GAME-05 | Scrollbare Panels sind für den Agenten nicht als Spieleraktion modelliert | Workshop-/Dossier-UI verwendet `ScrollContainer`; der Agent erhielt aber keinen `runtime_scroll`-Call und keine Scroll-Fähigkeitsbeschreibung | 0.98 | 0.02 |
| GAME-06 | Ein sichtbarer Button kann außerhalb des aktuell sichtbaren Panelbereichs liegen | UX-Suche filtert außerhalb des Viewports; ohne Scroll-Plan bleibt der Button unsichtbar | 0.94 | 0.06 |
| GAME-07 | Der SceneTree ist als Diagnosequelle zu groß für direkte Agentenkontexte | Der Runtime-Baum enthält Spiel-, UI-, Autoload- und Overlay-Knoten; ein Gesamtbaum entspricht nicht dem menschlichen Blick | 0.99 | 0.01 |

### Spielernahe Scroll-Regel

Ein Panel wird als scrollbar behandelt, wenn der sichtbare Scan einen `ScrollContainer`-Ancestor, abgeschnittene Controls, `truncated=true`, eine sichtbare Scrollbar oder einen Gate-/Abschnittstext ohne sichtbare Aktion zeigt. Der nächste Spielerzug ist dann ein separates `runtime_scroll`-Atom über dem Panel, danach ein neuer begrenzter Scan. Keine direkte Änderung von `scroll_vertical` per Code.


| ID | Befund | Evidenz | Diagnose-Sicherheit | Wahrscheinlichkeit Diagnose falsch |
|---|---|---|---:|---:|
| GAME-01 | Sichtbare Werkstatt verlangt eine orbitale Werft | Paneltext `Keine eigene Werft vorhanden — zuerst Orbitale Werft bauen.` | 0.98 | 0.02 |
| GAME-02 | Forschung/UI und State-/Log-Sicht sind nicht synchron | Forschungsbutton blieb disabled; State-/Log-Beobachtung meldete Abschluss | 0.75 | 0.25 |
| GAME-03 | Planetenauswahl ueber angenaeherte Bildschirmkoordinate ist unzuverlaessig | `(160,90)` liess `KEIN PLANET AUSGEWAEHLT`; Node-Pfad-Klick funktionierte | 0.90 | 0.10 |
| GAME-04 | Der konkrete Weg von Werft-Design zu orbitaler Werft ist noch nicht vollstaendig erkundet | Run endete vor der sichtbaren Ausbauaktion | 0.99 | 0.01 |

Moegliche Erklaerungen fuer GAME-02 sind UI-Refresh-Verzoegerung, falscher Abschlussindikator oder ein zusaetzliches Planeten-Ausbau-Gate. Keine davon darf ohne neuen Live-Scan als Fakt behandelt werden.

## Chain- und Diagnose-Regel

Chains sind für bereits erkundete, wiederholbare Teilstrecken geeignet, nicht für die Erstentdeckung des Spiels. Zulässig ist z. B. `find sichtbares Ziel -> mouse_move -> click -> wait -> bounded scan -> assertion`; jeder Chain-Schritt bleibt ein einzelner MCP-Tool-Call. `runtime_chain_validate` muss vor `runtime_chain_run` erfolgreich sein.

Die Validierung blockiert Composite-Tools, sichtbare GameState-/Goal-Abkürzungen, unbegründete Screenshots, fehlende Toolnamen, fehlende Args und überlange sichtbare Chains. Für Endgame-Tests werden Chains in Segmente von höchstens 20 sichtbaren Schritten geteilt, mit Assertions und No-progress-Abbruch zwischen den Segmenten. `runtime_chain_trace` liefert pro Schritt Dauer, Status, Ergebnis und Fehlerklasse.

SceneTree-Zugriffe verwenden standardmäßig `root_path`, `max_depth` und `max_nodes`; erst bei einem konkreten unbekannten Panel wird der Scope erweitert. Der Agent erhält damit eine sichtbare, begrenzte UI-Repräsentation statt eines Gesamtbaums.

## Diagnose-Regel

Die Prozentwerte sind keine Messung der Spielwahrscheinlichkeit. Sie geben nur an, wie wahrscheinlich die jeweilige aktuelle Diagnose bei der vorhandenen Evidenz falsch sein kann. Bei widerspruechlichen Signalen gilt: sichtbarer UI-Zustand beschreibt die Spieleroberflaeche; State/Logs sind read-only Zusatzdiagnostik; MCP-Transportfehler werden separat klassifiziert. Bei fehlendem Beweis bleibt das Finding `UNKNOWN`.

## Naechster Agent

1. Nicht `first_ship_atomic.js` und nicht `runtime_goal_sequence` starten.
2. Frischen sichtbaren Godot-Prozess mit TCP-MCP starten und Listener pruefen.
3. Einzeln: `scan -> find -> mouse_move -> scan -> click -> wait -> scan`; jeden Befehl separat starten.
4. Fuer Planetenauswahl zuerst sichtbaren SceneTree-/Node-Pfad bestaetigen; keine geratenen Koordinaten.
5. Vor jeder Forschung oder jedem Bau zuerst exakten sichtbaren Buttontext, `disabled` und Node-Pfad protokollieren.
6. Nach jedem Klick getrennt protokollieren: Game-Mismatch, MCP-Mismatch, Unsicherheit.
7. Erst bei sichtbarer Schiffsliste oder sichtbarem Montage-Erfolg `PASS` melden.

## Autonomie-, Freeze-, Rollback- und Editor-Modi

Diese Checks sind keine Spieleraktionen und werden getrennt ausgefuehrt:

- Freeze/Step: `runtime_e2e_run` mit Szenario `freeze_step` prueft deterministische Pause-/Frame-Fortschaltung.
- Workspace-Rollback: `mcp_autonomy_write_gate_test.gd` und `mcp_workspace_contract_test.gd` pruefen Write-Gate, Journal, Einzel-Rollback und `rollback_all`.
- Editor-Tooling: `gdscript_mcp_plugin.gd` stellt SceneTree, Node-/Property-Aktionen, Undo/Redo, Transaktionen und Screenshot bereit. Editor-Schreibzugriff bleibt standardmaessig deaktiviert und muss separat ueber den Editor-Dock freigegeben werden.
- Sichtbarkeit: `mcp_test_runner.gd` verweigert Headless-Ausfuehrung fuer MCP-Live-Tests. Headless Contract-/Build-Tests sind davon getrennt und beweisen keine sichtbare Spielerfunktion.

Testergebnisse werden unter `docs/mcp_live_test_results.md` fortgeschrieben. Keine Testzeile darf aus einem Headless- oder Editor-Test einen Live-Gameplay-PASS ableiten.
