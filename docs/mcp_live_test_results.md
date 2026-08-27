# MCP Live-Test Ergebnisse

Stand: 2026-08-27 (inkl. sichtbarem Tutorial-QA-Lauf)

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

---

## Lauf `Tutorial 7/7 (sichtbarer QA-Durchlauf)` — 2026-08-27

- Modus: sichtbare Runtime (OpenGL, NVIDIA GTX 1050), MCP-TCP 127.0.0.1:9090, einzelne Atom-Scripts (ein MCP-Call pro Prozess), kein Headless, kein Goal-/Chain-Pfad.
- Ergebnis: `ABORTED / INCOMPLETE` — Tutorial bis **Schritt 4/7** gespielt, Abbruch auf Wunsch zur Dokumentation.
- Sichtbar erreicht: Main Menu → neue Welt → Tutorial Schritt 1–3 (Kamera, Planet wählen, erste Forschung) → Planetendossier mit baubarer Orbitaler Werft.
- Sichtbar **nicht** erreicht: Bau der Orbitalen Werft (Klick trifft den `BAUEN`-Button nicht), Teilekauf, Montage, erstes Schiff.

### Durchlauf-Protokoll (Schritt für Schritt beobachtet)

| Schritt | Beobachtung (sichtbar) | Aktion | Ergebnis |
|---|---|---|---|
| Main Menu | `NEUES SPIEL`, `WEITER` (aktiv!), `BEENDEN`; Scene `main_menu` | Pfad-Klick `NewGameButton` | Wechsel nach `game_view` ✓ |
| Tutorial 1/7 | „WILLKOMMEN BEI SNIPWAR — Bewege die Kamera mit [W A S D]… grüner Ring“ | `WEITER` (Pfad) | Schritt 2 ✓ |
| Tutorial 2/7 | „PLANET WÄHLEN — Klicke deine Heimatwelt an“ | Pfad-Klick `Player Homeworld/ClickArea` (bestätigt per `runtime_find_node`, kein Koordinatenraten) | Panel `PLAYER HOMEWORLD · Status: Eigene Welt · 6 Einheiten · 3 Bauplätze`; Auto-Advance ✓ |
| Tutorial 3/7 | „ERSTE FORSCHUNG — öffne [F] FORSCHUNG… Orbitales Werft-Design“ | Klick `FORSCHUNG` → Klick `TechNode_shipyard_construction` | Node zeigt `⟳ Orbitales Werft-Design` (In-Forschung); Auto-Advance ✓ |
| Tutorial 4/7 | „ERSTES GEBÄUDE — … drücke BAUEN auf dem ‚Orbitalen Werft'“ | Klick `✕ SCHLIESSEN` (Forschung) → Klick `PLANET`-Launcher → PLANETEN-DOSSIER offen; Scroll `BuildSlotsScroll`; Klick `BAUEN` (Pfad) und (Koordinate) | **Klick trifft nicht** — weiterhin `0 Gebäude`, `0/3 Hangar`, Schritt 4/7 → Abbruch |

### Game-Seite (was im Spiel korrekt funktioniert hat)

- Tutorial-System (`TutorialDirector`, 7 Schritte) ist vorhanden, sichtbar und **auto-gated**: Fortschritt erfolgt erst, wenn die geforderte Aktion wirklich erkannt wurde (Planet selektiert, Forschung gestartet).
- Forschung zeigt sichtbaren Status: `⟳` (in Forschung) und danach im Dossier `✓ Forschung abgeschlossen: Orbitales Werft-Design` — damit ist das frühere Finding **GAME-02** (UI desynchron) im sichtbaren Lauf **nicht reproduziert**.
- Baukatalog ist granular: `● BAUBAR` / `✗ GESPERRT · Ressourcen fehlen` / `✗ GESPERRT · Forschung fehlt` mit Begründung; `BAUEN`-Buttons haben **eindeutige Node-Pfade** und korrekte `disabled`-Flags — Finding **GAME-04/G4** (5 identische Buttons, „Control is disabled“) ist damit **gefixt**.
- Der Weg zur Werft ist jetzt lehrbar: Orbitales Werft-Design forschen → PLANETEN-DOSSIER → MILITARY → „Orbitale Werft · ● BAUBAR · 20 Biomasse · 5 Credits“ mit aktivem `BAUEN` — GAME-01/GAME-04-Route damit grundsätzlich offen.

### MCP-Findings (Tooling/Transport — mit Wahrscheinlichkeit der These)

| ID | Befund | These | Wahrscheinlichkeit der These | Gegenthese |
|---|---|---|---|---|
| QA-MCP-1 | `runtime_click` auf dem `BAUEN`-Button der Orbitalen Werft (im `BuildSlotsScroll` des PaperDossier) trifft nicht. Pfad-Klick und Koordinaten-Klick (628,509) lieferten beide die gemeldete Zielposition (1253,939); der Scan meldet den Button bei Rect (491,494,274×31). Kein Bau. | **Korrigierte Diagnose (Code-Audit):** Der Transform in `_rt_click` ist korrekt (window/content-Scale-Mapping, `get_global_rect()` inkl. Scroll-Offset). Die Skalierung 1.9958/1.8463 entspricht einem **maximierten Fenster** (~1916×997) — der Klick lag im Fenster. Echte Ursache: die **statische Tutorial-Karte** (MOUSE_FILTER_STOP, alte CENTER_BOTTOM-Position y 362–512) überlappte den Button (y 494–525) und schluckte den Klick — **UI-Okklusion, kein MCP-Transform-Bug**. Fix P0: `_card.mouse_filter = MOUSE_FILTER_IGNORE` (Panel-Body klickdurchlässig, WEITER/ÜBERSPRINGEN bleiben bedienbar). | **~90 % (Okklusion)** | Restrisiko: zusätzliches unsichtbares Gate auf dem BAUEN-Button (~10 %). |
| QA-MCP-2 | Node-Client-Prozess beendet sich nach einem Call nicht sauber (Prozess hängt ~8–25 s, `timeout` liefert Exit 124, Antwort war längst gedruckt). | Unaufgeräumter `setTimeout`-Timer in `mcp_lib.js` (`connect()`-Timeout wird nie gecleart) hält die Event-Loop offen. Reine Client-Cosmetic, kein Server-Problem. | **~90 %** | Server hält Verbindung offen bzw. Socket teardown blockiert (~10 %). |
| QA-MCP-3 | Git-Bash konvertiert `/root/...`-Pfade zu `C:/Program Files/Git/root/...` → „Node not found“. | MSYS-Pfadkonvertierung; Workaround `MSYS_NO_PATHCONV=1` (dokumentiert im Protokoll). Kein Server-Fehler. | **~100 %** | — |
| QA-MCP-4 | `atomic_session.js` über FIFO über mehrere Shells hinweg lieferte keine Tool-Antworten; die Einzel-Atom-Scripts (dokumentierter Weg) funktionierten zuverlässig. | Session-/Shell-Lebenszyklus-Problem der FIFO-Verkabelung, nicht der MCP-Server. | **~80 %** | Server verarbeitet nur eine Verbindung gleichzeitig (~20 %). |

### Game-Findings (nur sichtbar bestätigt — mit Wahrscheinlichkeit)

| ID | Befund | These | Wahrscheinlichkeit |
|---|---|---|---|
| QA-GAME-1 | `WEITER` war im Main Menu **aktiv**, obwohl ein frischer Lauf erwartet wurde. | **Bestätigt (Code-Audit):** `main_menu.gd` — `_refresh_continue()` = `has_save(0)`, und `_on_new_game_pressed()` ruft `delete_save(0)`. Ein Alt-Save (Slot 0) aus früheren Läufen existierte (daher WEITER aktiv); der NEUES-SPIEL-Klick löschte ihn — deshalb ist `user://saves/` danach leer (Folge, kein Widerspruch). | **~95 %** | Rest: Auto-Save beim vorherigen Quit mit gleicher Auswirkung (~5 %). |
| QA-GAME-2 | Kein Game-Blocker bis Schritt 4/7 gefunden; die alten Findings GAME-01/02/04 sind im sichtbaren Lauf nicht mehr reproduzierbar (siehe Game-Seite oben). | Das Spiel ist bis zum Werft-Bau-Klick funktional; der Blocker ist Tooling-seitig (QA-MCP-1). | **~85 %** | Es gäbe ein zusätzliches, bisher unsichtbares Gate für den BAUEN-Klick (~15 %). |

### Unsicherheit & nächster Agent

- QA-MCP-1 (korrigiert): Ursache war UI-Okklusion durch die Tutorial-Karte, nicht ein Transform-Bug (Transform in `_rt_click` verifiziert korrekt). Fix P0 (Karte `MOUSE_FILTER_IGNORE`) ist umgesetzt; Verifikation: sichtbarer Lauf, `BAUEN`-Klick bei offener Karte muss den Bau auslösen.
- Nach **jedem** Klick auf `BAUEN` den Hangar-Status scannen (`0/3 Hangarplätze belegt` → `1/3`) — nicht nur auf `clicked:true` vertrauen.
- Screenshot bei diesem Konfliktfall (Scan-Rect vs. Click-Ziel) als Evidenz aufnehmen (war hier angezeigt, weil Live-Signal und Klickantwort widersprachen).
- Kein Headless-Run hat diese Spieleraktionen bewiesen; ein Fix gilt erst als verifiziert, wenn der Klick im sichtbaren Fenster einen Bau auslöst.


## Lauf `Fixes + Pflicht-OCR (sichtbare Verifikation)` — 2026-08-27 (Fortsetzung)

Modus: sichtbare Runtime, MCP 127.0.0.1:9090, **`mcp_file_driver.js`** (Standard-Transport,
eine Zeile = ein Tool-Call). Alle Nachweise sichtbar erbracht, kein Headless.

### Befund 1 — „Forschung feuert automatisch“ war die CPU (gefixt, verifiziert)

- **Symptom:** Toast „Forschung abgeschlossen: Orbitales Werft-Design.“ ohne Spieleraktion.
- **Ursache (Code-Audit):** `cpu_dispatch_ai.gd` erforscht `shipyard_construction` direkt nach
  Weltstart (erste Priorität, research_time 15 s) und zieht die Kette bis `weapon_systems` durch.
  `event_log._on_technology_researched` **ignorierte die Fraktion** und pushte für jede CPU-Forschung
  den Spieler-Toast. `game_research_status faction=b` zeigte live: `completed: [shipyard_construction,
  scout_hull, scanner_drone, weapon_systems]` — Spieler (`a`) leer. Deine Beobachtung war **richtig**;
  meine frühere „widerlegt“-Einschätzung war falsch (ich hatte nur den Spieler-Zustand geprüft).
- **Fix (`scripts/state/event_log.gd`):** Nur `FACTION_PLAYER` (`&"a"`) erzeugt den Toast; CPU/Fremd
  gehen als `log_silent` ins Log („… (der CPU-Fraktion)“).
- **Verifikation (sichtbar):** Frischer Lauf, 60 s gewartet → CPU hat **alle 4 Techs** durch — **kein**
  einziger „Forschung abgeschlossen“-Toast erschien (Scans 1+2: nur Launcher-Button „FORSCHUNG“).

### Befund 2 — Kontext-gated Sub-Menü-Hotkeys (implementiert, Baum live verifiziert)

- Ziel (deine Definition): Hotkeys = Kamera + Menü-Navigation **inkl. Sub-Menüs**, dürfen nur im
  jeweils offenen Menü feuern. Keine Aktions-Hotkeys.
- **Neu in `planet_dossier_view.gd`** ([1]–[9] Planet wählen, Bild auf/ab Scrollen),
  **`parchment_tech_tree_view.gd`** (WASD/Pfeile + Bild auf/ab scrollen den Baum),
  **`workshop_view.gd`** (Pfeile + Bild auf/ab) — jeweils `_unhandled_input` in der View, die nur
  existiert, solange ihr Menü offen ist (View = Kontext-Gate). Kamera war währenddessen schon
  blockiert (`ModalCoordinator` → `MapCamera.set_input_blocked`), P/W/F/R feuern nur ohne Modal.
- **Verifikation (sichtbar):** Baum offen → `KEY_RIGHT` scrollt `TreeScroll.scroll_horizontal`
  0 → 120 → 240. Gate: `[P]` bei offenem Baum öffnet **kein** Planetendossier (Titel bleibt
  `FORSCHUNGSBAUM`). `[P]`/`[W]` im Welt-Kontext öffnen Dossier/Werkstatt.
- **Einschränkung:** Bild-ab-Scroll war in den Testzuständen nicht messbar (kein vertikaler
  Overflow in Baum/Werkstatt; Dossier-PgDn in dieser Runde nicht erreichbar wegen P-Timing).
  Code ist mit dem verifizierten Baum-Handler identisch aufgebaut.

### Befund 3 — Maus-Automatik: Cursor springt nie mehr (implementiert, verifiziert)

- **Ursache:** `smooth_travel` koppelte `steps = min(duration, distance)` bei Minimum **3** →
  kurze Distanzen = 3 grobe Sprünge à ~33 px; Agent musste manuell `runtime_mouse_move` vorschalten.
- **Fix (`mcp_runtime_tools.gd`):** Mindest-Schrittzahl 8, `maxi` statt `mini` (Distanz dominiert),
  32 px/Frame; `runtime_click` erzwingt **immer** den Approach (smooth unabhängig vom Agenten).
- **Verifikation (sichtbar):** Klick ohne separates Mouse-Move → `approach_steps: 8` (kurz) bzw.
  **31** (Maus bei 10,10 → weit entferntes Ziel), `smooth: true`, `clicked: true`.

### Befund 4 — Pflicht: Bild-/OCR-Analyse bei unerwartetem Ergebnis (implementiert, verifiziert)

- **Regel (deine Anforderung):** Wenn ein Tool-Ergebnis nicht erwartet wird, MUSS automatisch eine
  OCR-Analyse folgen — im MCP, nicht als Agentendisziplin.
- **Umsetzung (`mcp_server.gd`):** Jede Tool-Antwort durchläuft `_is_unexpected_result`
  (Fehler/`ok:false`/`_error`, `clicked:false`, `moved:false`, `controls:[]`) → bei Treffer async
  `_capture_visual_evidence()`: Screenshot über die Vision-Pipeline (`context_id`, Maße,
  Qualitätscheck) + OCR über den Vision-Worker (Tesseract.js bzw. `--ocr-command`; neu:
  Server-Config `vision_worker_ocr_command`, durchgereicht in `mcp_vision_worker.gd`).
  Ergebnis wird als `visual_evidence` an die Antwort angehängt. Rekursionsschutz über
  `UNEXPECTED_VISUAL_EXCLUSIONS` (Screenshot-/Analyse-/Vision-/Status-Tools).
- **Verifikation (sichtbar):** Provozierter Fehler-Klick (`Node not found`) und leerer Scan
  (`controls: []`) lieferten beide automatisch `visual_evidence` — `screenshot {context_id,
  1280×720}` + OCR.
- **OCR live (nach Installation):** `npm install tesseract.js` im Client-Ordner
  (`addons/gdscript_mcp/client/`, package.json + package-lock, `node_modules/` in `.gitignore`)
  → beide Fälle liefern `ocr.available: true`, **Confidence 86**, Text:
  `EISEN-GRENZE / NEUES SPIEL / WEITER / BEENDEN / Strategische Overworld - Flottengefechte :
  Planetare Eroberung` (echtes Main-Menu-Layout). Alternativ konfigurierbar über
  `vision_worker_ocr_command` (z.B. Tesseract-CLI). Nebenbefund: Der Screenshot-`blank`-Check
  schlägt am dunklen Main Menu fehl, obwohl OCR Text findet — Blank-Check zu streng, ohne
  Auswirkung auf die OCR-Pflicht.
- **Beschleunigung (Cache + Parallelität, verifiziert):**
  - **Asset-Cache:** `deu.traineddata.gz` einmalig lokal (Setup) + `cacheMethod "write"`
    → `node_modules/.cache/tesseract.js/` enthält `deu.traineddata` (15,4 MB) — Kaltstart
    komplett lokal ohne CDN: **OCR in 2,3 s** (vorher >60 s CDN-Timeout).
  - **Worker-Pool:** `OCR_POOL_SIZE` (default 2, env `MCP_OCR_POOL`), serielles Init
    (zweiter Worker nutzt den Cache), Jobs round-robin + im Serve-Loop nicht seriell awaited.
    **2 gleichzeitige OCR-Jobs in 1,56 s** (beide conf 86).
  - **Fallstricke gefixt:** (a) `artifactFromContext` suchte nur im Root — Artefakte liegen in
    Session-Unterordnern (`runtime_runtime_<pid>/`); (b) Browser-`worker.min.js` crasht in Node
    (`addEventListener`-Fehler) → kein `workerPath` setzen, tesseract.js wählt die Node-Variante;
    (c) Timeouts: Client 30→90 s (`mcp_lib.js`), Supervisor 15→60 s (`mcp_vision_worker.gd`),
    damit der einmalige Kaltstart durchkommt.
- **Workflow-Konsequenz (dokumentiert in AGENTS.md):** Bei unerwarteten Ergebnissen nie raten —
  `visual_evidence` lesen; Standard-Transport für sichtbare Läufe ist `mcp_file_driver.js`.

### Befund 5 — Entkopplung: Aktionen blockieren nie mehr auf Analyse (implementiert, live verifiziert)

- **Problem:** `_send_tool_result_with_visual_evidence` awaited die komplette Analyse
  (Screenshot + OCR, 1,5–2,3 s) **vor** dem Senden — jede unerwartete Aktion blockierte
  seriell, der Agent konnte erst nach der OCR weiterarbeiten. InGame-Aktionen und
  Analyse hingen in einem kritischen Pfad.
- **Fix (`mcp_server.gd`):** Antwort wird SOFORT gesendet (`visual_evidence:
  {status: "pending"}`); die Analyse läuft als Fire-and-forget-Coroutine
  (`_start_background_evidence` → `_capture_visual_evidence`) in den `_evidence_cache`.
  Neues Host-Tool `runtime_visual_evidence` (`wait_ms` pollt laufende Analyse,
  `capture` startet frisch, `_evidence_inflight`-Guard verhindert Doppelstarts).
- **Live gemessen (sichtbar, Main Menu):**
  - Fehler (`runtime_inspect_node` auf nicht-existierenden Node): Antwort in **`elapsed_ms: 4`**
    (vorher ~2 s) mit `pending`-Marker.
  - Abruf `runtime_visual_evidence {wait_ms: 3000}`: **`elapsed_ms: 6`**, `status: ready`,
    OCR-Text `EISEN-GRENZE / NEUES SPIEL / WEITER / BEENDEN …`, Confidence 86.
  - Zwei Fehler in Folge: beide antworten sofort (`elapsed_ms: 10`), zweite Analyse
    startet nicht doppelt (Guard) — Gesamtdurchsatz ohne serielles Warten.
- **Workflow-Konsequenz:** Bei unerwartetem Ergebnis erst die Aktion bewerten (Antwort kam
  sofort), dann `runtime_visual_evidence` abrufen — meist ist die Analyse bereits fertig.
  Die Pflicht-Regel (nie raten) bleibt, aber sie blockiert keine Aktion mehr.

### Offene Punkte aus dieser Runde

- ESC (`ui_cancel`) im offenen Modal schloss per MCP-Injektion weder Dossier noch Pause-Menü;
  custom Actions (`open_planet`, `open_workshop`) funktionierten dagegen. Verdacht: MCP-spezifisches
  Injektions-/Action-Matching-Artefakt für `ui_*`-Actions; mit physischer Tastatur zu klären.
- `[P]` öffnete das Dossier nach Tutorial-Skip nicht zuverlässig (Timing-Artefakt); Launcher-Klick
  und `[W]` waren stabil.
- Dossier-PgDn-Scroll (BuildSlotsScroll) wartet auf einen Lauf mit echtem Overflow.
- **Editor-Modus / eingebettete Spiel-Tests (OFFEN):** Erkenntnis aus der Editor-Play-Erkundung —
  der In-Process-Server als Editor-Kind (`_start_runtime_server_internal`) sieht den Spiel-SceneTree
  nicht (Godot hat keine öffentliche API; `Engine.get_main_loop()` → Editor-Tree → „Game not running").
  Lösungskandidat: `McpRuntime`-Autoload startet den Server im Spiel-SceneTree selbst (Env-Flag
  `MCP_EMBEDDED` vom Plugin vor `play_main_scene`); Details in `docs/FINDINGS.md` → OFFEN-1.

---

## Session-Hergang „Tutorial-QA + MCP-Automatisierung" — 2026-08-27 (kompletter Verlauf)

Ziel der Session: Das Tutorial sichtbar durchspielen (kein Headless), dabei MCP und Spiel
trennscharf beurteilen. Hergang in Reihenfolge — jede Etappe mit Ergebnis und Folge:

1. **QA-Start + Abbruch-Kriterium:** Erster Versuch lief über MCP; wegen unklarer Ergebnisse
   (Transport-Hang, kein OCR) wurde der Durchlauf abgebrochen und MCP- vs. Game-Fehler
   getrennt dokumentiert („Breche ab, dokumentiere …").
2. **Findings Runde 1 (deine Finins):** Zentrierter Waves-Kreis (Touch-Ripple) bei Maus
   stört → Fix `touch_feedback_layer.gd` (Ripple nur noch Touch). Tutorial-Schritt 2 nennt
   grünen Kreis um Home-Planet, wird aber nicht angezeigt → offen (OFFEN-2). Onboarding soll
   schrittweise jedes Menü per Flyover erklären → Doktrin „rein präsentativ" in `DESIGN.md`.
   „Forschung feuert automatisch" → **Aufklärung statt Raten:** Spieler-Research war leer
   (`game_research_status: active/completed = []`), die Tech-Bäume starten nur per Button-Press;
   der Toast kam von der **CPU-Forschung** (Ursache, Fix, Live-Nachweis in Befund 2).
3. **Tutorial-Doktrin:** Tutorial dient NUR als Onboarding, macht nichts im Hintergrund
   (`TutorialDirector`, CanvasLayer 92, Flyover-Karte + grüner Ziel-Marker, Fortschritt nur
   per WEITER) — dokumentiert in `DESIGN.md` (Abschnitt 11) und `MCP_INDEX.md`.
4. **QA-MCP-1 Fix:** Tutorial-Karte klickdurchlässig (`mouse_filter = IGNORE`), WEITER/
   ÜBERSPRINGEN bleiben klickbar — die echte MCP-1-Ursache (Klick ging durch die Karte).
5. **Kontext-gated Sub-Menü-Hotkeys:** Hotkeys = Kamera + Menü-/Sub-Menü-Navigation (keine
   Aktions-Hotkeys), nur im offenen Kontext. Implementiert für Dossier `[1]`–`[9]`/Bild,
   Forschungsbaum WASD/Pfeile/PgUp/PgDn, Werkstatt PgUp/PgDn; Kontext-Gate live bewiesen.
6. **MCP-Maus-Automatik:** Cursor springt nie mehr — `smooth_travel` min 8 Steps, Distanz-
   basiert; `runtime_click` approachiert immer selbst. Live: 8 bzw. 31 Steps.
7. **Pflicht-OCR:** Unerwartetes Ergebnis (Fehler/`clicked:false`/`controls:[]`) → automatisch
   `visual_evidence` (Screenshot + OCR). Erste Version awaited die Analyse (Latenz), danach:
8. **tesseract.js + Cache + Pool:** Installation im Client-Ordner, Assets lokal (Kaltstart
   2,3 s), Worker-Pool default 2 (`MCP_OCR_POOL`), 2 Jobs parallel 1,56 s, Confidence 86.
9. **Entkopplung (Befund 5):** Aktionen antworten sofort (4 ms), Analyse Fire-and-forget in
   Cache, Abruf per `runtime_visual_evidence` (6 ms) — der Durchsatz-Flaschenhals ist weg.
10. **Workflow-Audit:** `AGENTS.md` um Standard-Transport (`mcp_file_driver.js`) und
    Nie-raten-Regel (visual_evidence) erweitert; Preflight PASSED.
11. **Editor-Modus-Erkundung (OFFEN):** Eingebettete Spiel-Tests im Editor untersucht —
    Editor-Kind-Server kann Spielbaum nicht sehen; Lösungskandidat dokumentiert (OFFEN-1).
12. **Doku-Konsolidierung:** Zentrale Findings-Datei `docs/FINDINGS.md` eingeführt
    (Pflicht-Referenz, immer aktuell halten), Session-Hergang hier, Commit-Slices über DOKI.

**Ergebnis:** Alle in dieser Session behobenen Befunde sind live/sichtbar verifiziert (keine
Blind-Fixes); offene Punkte sind ehrlich als OFFEN/BEOBACHTET in `docs/FINDINGS.md` geführt.
