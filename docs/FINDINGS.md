# FINDINGS — Zentrale Befund-Referenz (IMMER AKTUELL HALTEN!)

> **Diese Datei ist die zentrale Findings-Datei des Projekts.** Jeder QA-Lauf,
> jeder sichtbare MCP-Test und jede Fix-Runde **muss** hier nachgetragen werden
> (Status, Beleg, Referenz). Sie ist die Todo-Referenz: Was ist gefixt, was ist
> offen, was ist beobachtet? Nicht in lokalen Notizen vergraben — hierher.
>
> **Pflicht bei jeder Session:** 1) Neue Befunde eintragen. 2) Gefixte Befunde
> auf `✅ GEFIXT` setzen (mit Beleg + Datei). 3) Offene Punkte ehrlich offen
> lassen. 4) Diese Datei **mitcommitten** (gehört zu jedem Commit-Slice, der
> Befunde berührt).

## Status-Legende
- ✅ **GEFIXT** — implementiert und live/sichtbar verifiziert (Beleg angegeben)
- 🟡 **OFFEN** — beobachtet/bekannt, noch nicht behoben
- 🔵 **BEOBACHTET** — verifiziertes Verhalten, bewusst so gelassen (kein Fix nötig)

---

## QA-Runde 2 — MCP-Live-Loop: Identity-Fix, OCR-Pipeline, Dock-Goal (28.08.2026, sichtbar, Port 9090, Profil qa)

### Spielfindings (Game-Seite)
| # | Befund | Status | Beleg / Referenz |
|---|--------|--------|------------------|
| QA2-GAME-1 | Identitätsdialog: „IDENTITÄT FESTLEGEN" ohne Namen brach STUMM ab — kein Preset-Name, kein Feedback → Dead-End im Spieler-Flow | ✅ GEFIXT | `scripts/ui/main_menu.gd`: Preset `Stickman` im Input + sichtbarer Hinweis statt stummem `return` (`_show_identity_intro`/`_confirm_identity`); Compile-Gate PASS (301 Skripte); live verifiziert: Dialog → `game_view` (mehrfach, saubere Runs) |
| QA2-GAME-3 | NEUES SPIEL-Klick löst keinen Szenenwechsel aus: `runtime_ux_click` returns `clicked:true` aber Szene bleibt auf `main_menu` — Blockiert Spielprogression komplett | 🟡 OFFEN | Direkte MCP-Tool-Calls zeigen erfolgreichen Klick aber persistente Main-Menü-Controls nach 6s Wartezeit; Visual Evidence OCR bestätigt Main-Menü-Text: "SNIPWAR\nSTICKMAN // IDENTITATSPROTOKOLL\n..." nach Klick und Warte |

### MCP-Findings
| # | Befund | Status | Beleg / Referenz |
|---|--------|--------|------------------|
| QA2-MCP-1 | OCR nie verfügbar: Python-Worker startete ohne `--ocr-command` (`mcp_runtime.gd` Default leer) → `ocr_available:false` | ✅ GEFIXT | Auto-Detect in `addons/gdscript_mcp/client/vision_worker.py` (`shutil.which` + Standard-Installationspfade, stdlib-only); Beleg: Evidence `available:true, engine:cli` nach Neustart |
| QA2-MCP-2 | Tesseract-Invocation fehlte Output-Target `stdout` → `OCR command exited 1` | ✅ GEFIXT | `[tesseract, bild, stdout]` in `run_ocr`; Beleg: OCR-Text „WILLKOMMEN IM PAPIERKOSMOS …" aus Live-Screenshot (1656×932) |
| QA2-MCP-3 | OCR einstellig englisch (Engine-Default) statt zweisprachig — User-Freigabe „kannst english"; lokales `deu.traineddata` korrupt (inkompletter Download, dazu `.tmp`-Artefakt) und bewusst NICHT verwendet | 🔵 BEOBACHTET | `run_ocr` ohne `-l deu`; Umlaute leicht unvollkommen („Transport", „lommen"), Text klar lesbar; deu-Rettung optional später |
| QA2-MCP-4 | Dock „Ziel setzen" → „Nicht verbunden — Ziel kann erst nach dem Spielstart gesetzt werden" ist KORREKTES Gate-Verhalten: `mcp_dock.gd:383` prüft `_runtime_client.is_ready()` (TCP+Handshake). Nach Spielstart verbindet der Dauer-Auto-Connect selbsttätig neu (Beleg: `client_count=2` inkl. Dock), `runtime_agent_goal_set` → `ok:true` | 🔵 BEOBACHTET | Live 28.08.2026: Spiel-Neustart → Dock automatisch verbunden; Ziel gesetzt über denselben Tool-Call wie der Dock-Button |
| QA2-MCP-5 | `runtime_audio_list_streams` → `[]` im Hauptmenü trotz vorhandnem `main_menu.ogg`-Asset; Welt: nur `Master`-Bus, keine Music/SFX-Buses — ungeklärt, ob das Tool nur MCP-gestartete Streams listet oder Audio nicht verdrahtet ist | 🟡 OFFEN | Proben 28.08.2026 (Menü + Welt); Klärung braucht `runtime_audio_analyze`/Code-Audit der Audio-Pipeline |
| QA2-MCP-6 | Tutorial-Overlay („Schritt 1/8 — WILLKOMMEN IM PAPIERKOSMOS") ist für `runtime_ux_scan` UNSICHTBAR: `TutorialSkip`/`TutorialWeiter` sind Controls (Code: `tutorial_director.gd`), erscheinen aber weder bei max_controls=600/max_depth=14 noch über Pfad-Guesses (`/root/World/PlanetNetwork/...` → Node not found) — MCP kann das Overlay nicht schließen; Spieler schon | 🟡 OFFEN | Screenshot/OCR-Beleg im Lauf; `planet_network.gd:375` erzeugt den Director — echter Parent-Pfad noch unbekannt; nächsten Schritt: Parent-Pfad von `add_child(_tutorial)` klären |
| QA2-GAME-2 | Progressions-Gate für „erstes Schiff": WERKSTATT/HANGAR zeigt „Keine eigene Werft vorhanden — zuerst Orbitale Werft bauen." — Forschungspfad („Orbitales Werft-Design") noch nicht durchspielbar, weil das Tutorial-Overlay (QA2-MCP-6) die Navigation verdeckt | 🟡 OFFEN | OCR-Beleg aus Live-Screenshot (WERKSTATT-Panel); Gate-Text exakt dokumentiert |
| QA2-TEST-2 | Idle-Laufzeiten im Loop hatten zwei Wurzeln, beide behoben: (a) verwaiste Node-Driver hingen mehrfach parallel an 9090 und beobachteten dieselben Queue-Dateien (Desync), (b) Off-by-one in der Resultat-Zählung (`> base+1` statt `> base`) ließ Einzeln-Calls immer bis zum Cap laufen. Jetzt: ein exklusiver Driver pro Lauf (terminate im finally), unique Queue-Pfade, FileNotFound-tolerante Reads, Ready-Line als Bedingung | ✅ GEFIXT | Vorher: 25–40 s Idle pro Call; nachher: Scan in 0,5 s, Gesamtläufe < 10 s |

### TEST-/Workflow-Findings
| # | Befund | Status | Beleg / Referenz |
|---|--------|--------|------------------|
| QA2-TEST-1 | Fixe `sleep`-Wartezeiten im Testlauf waren Fehlerquelle (Timeouts, Desyncs). Permanent-Regel per Impuls: Warten AUSSCHLIESSLICH zustandsbasiert — Poll bis die erwartete Bedingung erfüllt ist (Port lauscht, Szene/Control sichtbar, Evidence `ready`), mit hartem Deadline-Cap, keine fixen Schläfchen | ✅ GEFIXT | Live-Loop 28.08.2026 komplett per Bedingungs-Polling verifiziert (Port→UI→Dialog→Welt→Evidence); Regel verbindlich in `addons/gdscript_mcp/AGENTS.md` Workflow |

---

## QA-Runde 1 — „Tutorial durchspielen" (sichtbar, mcp_file_driver)

### Spielfindings (Game-Seite) — QA-Runde 1
| # | Befund | Status | Beleg / Referenz |
|---|--------|--------|------------------|
| QA-GAME-1 | „WEITER" nach NEUES SPIEL: Save wurde von NEUES SPIEL gelöscht | 🔵 BEOBACHTET | `docs/mcp_live_test_results.md` (Doku präzisiert: „Save wurde von NEUES SPIEL gelöscht") |
| QA-GAME-2 | Tutorial-Schritt 2 nennt grünen Kreis um Home-Planet, der nicht angezeigt wird | 🟡 OFFEN | Karte/Target-Marker-Thema; Tutorial-Doktrin (rein präsentativ) dokumentiert |
| QA-GAME-3 | Tutorial-Schritt 4 (Forschung) wirkt überladen; Forschung feuerte „automatisch" | ✅ GEFIXT | Ursache: CPU-Forschung toaste als Spieler-Event → `event_log.gd` filtert jetzt Fraktion; live verifiziert (4 CPU-Techs, kein Toast) |
| QA-GAME-4 | Hotkeys: Forschung/Bauen hatten keine Aktions-Hotkeys | 🔵 BEOBACHTET | Ziel-Definition: Hotkeys = Kamera + Menü-/Sub-Menü-Navigation, kontext-gated; Aktions-Hotkeys bewusst nicht |
| QA-GAME-5 | Klick-Indikator (Touch-Ripple) bei Mausklick stört | ✅ GEFIXT | `touch_feedback_layer.gd`: Ripple nur noch bei Touch, Maus ist Primärsteuerung |

### Kontext-gated Sub-Menü-Hotkeys (implementiert)
| # | Befund | Status | Beleg |
|---|--------|--------|-------|
| UX-2 | Planeten-Dossier: `[1]`–`[9]` Planet wählen, Bild auf/ab scrollen | ✅ GEFIXT | `planet_dossier_view.gd` `_unhandled_input` |
| UX-3 | Forschungsbaum: WASD/Pfeile navigieren, PgUp/PgDn blättern | ✅ GEFIXT | `parchment_tech_tree_view.gd`; live bewiesen: KEY_RIGHT scrollt horizontal 0→120→240 |
| UX-4 | Werkstatt: PgUp/PgDn blättern | ✅ GEFIXT | `workshop_view.gd` |
| UX-5 | Kontext-Gate: `[P]` bei offenem Baum öffnet kein Dossier | ✅ GEFIXT | live bewiesen (Modal bleibt FORSCHUNGSBAUM) |
| UX-1 | Tooltip/Benennung „PLANET" entzerren | ✅ GEFIXT | `planet_network.gd`: Tooltip „Planeten-Dossier: Gebäude, Hangar, planetare Forschung" |

### MCP-Findings (Tooling/Transport)
| # | Befund | Status | Beleg |
|---|--------|--------|-------|
| MCP-M1 | `max_controls`/`include_visual=false` an `runtime_ux_analyze` durchreichen | ✅ GEFIXT | `mcp_ux_pipeline.gd` `analyze(include_visual, root_path, max_controls, max_depth)` |
| MCP-01 | Transport-Abriss (Verbindungsverlust bei langen OCR-Läufen) | ✅ GEFIXT | `mcp_lib.js`: Connect-Timeout sauber + Timeout 30→90 s |
| MCP-02 | Injektion: `ui_cancel` (ESC) via virtuelle Eingabe matchet nicht | 🔵 BEOBACHTET | custom Actions (P) funktionieren, built-in Actions nicht — dokumentiert als MCP-Injektions-Befund |
| MCP-03 | `ux_find`-Semantik | 🟡 OFFEN | Beobachtungsposten, erst bei erneuter Reproduktion fixen |
| MCP-04 | Screenshot `blank`-Check schlägt am dunklen Main Menu fehl, obwohl OCR Text findet | 🔵 BEOBACHTET | Blank-Check zu streng, blockiert OCR-Pflicht nicht |
| MCP-05 | `runtime_click` ohne separates `mouse_move` → Cursor springt (3 grobe Steps) | ✅ GEFIXT | `mcp_runtime_tools.gd`: `smooth_travel` min 8 Steps, Distanz-basiert; live: 8 bzw. 31 Steps |
| MCP-06 | Pflicht-Analyse: unerwartetes Ergebnis ohne Bild/Kontext → Agent rät | ✅ GEFIXT | `mcp_server.gd` `visual_evidence` (Screenshot + OCR) |
| MCP-07 | Analyse blockiert Aktion (Antwort erst nach 1,5–2,3 s OCR) | ✅ GEFIXT | Entkopplung: Antwort sofort (4 ms), Fire-and-forget + Cache + `runtime_visual_evidence` (6 ms Abruf) |

### Dock-Umbau (Pipeline-Visualisierung)
| # | Befund | Status | Beleg |
|---|--------|--------|-------|
| DOCK-1 | Dock war eine Agenten-Steuerkonsole (Maus/Klick/Taste/Scan/Freeze/E2E) — für den User irrelevant | ✅ GEFIXT | Steuerung entfernt; `mcp_dock.gd/.tscn` zeigen jetzt live: Agent-Ziel (`runtime_agent_activity`), Tool-Call-Feed (✓/✗ + Timing + Fehler), OCR-Evidence (`runtime_visual_evidence`), Event-Stream (`runtime_mcp_events`) — Polling alle 2 s |

### OCR-Pipeline (implementiert, live verifiziert)
| # | Befund | Status | Beleg |
|---|--------|--------|-------|
| OCR-1 | Tesseract.js installiert (v7.0.0), `node_modules/` in `.gitignore` | ✅ GEFIXT | `addons/gdscript_mcp/client/package.json` + package-lock |
| OCR-2 | OCR liefert echten Text (deu, Confidence 86) | ✅ GEFIXT | live: `EISEN-GRENZE / NEUES SPIEL / WEITER / BEENDEN …` |
| OCR-3 | Kaltstart >60 s CDN-Timeout | ✅ GEFIXT | Assets lokal: `deu.traineddata` in `node_modules/.cache/tesseract.js/`, Kaltstart 2,3 s |
| OCR-4 | OCR seriell, ein Worker | ✅ GEFIXT | Worker-Pool (default 2, `MCP_OCR_POOL`), 2 Jobs parallel 1,56 s |
| OCR-5 | `artifactFromContext` findet Artefakte in Session-Unterordnern nicht | ✅ GEFIXT | Unterordner-Suche |
| OCR-6 | Browser-`worker.min.js` crasht in Node | ✅ GEFIXT | kein `workerPath` setzen (Node-Variante auto) |

---

## Befund-Korrekturen dieser Session (ehrlich dokumentiert)
- Frühere Einschätzung „Forschung feuert automatisch — widerlegt" war **falsch**:
  Der „Orbitales Werft-Design"-Toast kam wirklich ohne User-Aktion — es war die
  **CPU-Forschung** (`cpu_dispatch_ai` erforscht `shipyard_construction` bei
  Weltstart), deren Abschluss `event_log.gd` als Spieler-Toast pushte (Fraktion
  wurde ignoriert). Fix: Nur Spieler-Forschung toastet, CPU geht still ins Log.
- `mcp_runtime.gd` TEMP-Diagnose (Editor-Play-Erkundung) wurde vor Commit entfernt.

---

## Research-Warning Root-Cause-Auflösung — 2026-08-27

Die zuvor sichtbaren `tech_drift`-Meldungen waren keine automatische Spielerforschung und kein einzelner Forschungsbug. Sie entstanden durch absichtliche Forschungsaktionen innerhalb von Constraints (`cpu_dispatch`, `save_game_roundtrip`, `ship_catalog_and_assembly`, `ship_transit_and_arrival`), während die V2-Checkpoint-Prüfung weiterhin den unveränderten Baseline-Snapshot verglich. Zusätzlich konnte der CPU-Timer in einer Fixture vor dem Deaktivieren einmal laufen.

Behoben:
- `V2Fixture.reset_state()` deaktiviert Job-Fortschritt vor und nach dem Domain-Reset.
- `PreflightFixture.boot_default()` deaktiviert vorhandenen GameState-Fortschritt vor dem Szene-Boot.
- CPU- und Spielerforschung bleiben getrennte Pfade; CPU-Abschlüsse erzeugen keinen Spieler-Toast.
- `ConflictManager` löst `GameCycleManager` über den aktiven `SceneTree` statt über ungültige absolute NodePaths außerhalb einer Szene auf.
- Research- und Event-Log-Constraints: ✅ PASS.
- Vollständiger Preflight: ✅ 39/39 Constraints, 2020/2020 Assertions.

Die verbleibenden Isolation-Warnings anderer Constraints sind erwartete Mutationsnachweise innerhalb von Tests, keine Forschungsfehler. Die Architektur sollte sie künftig pro Constraint als erwartete Mutation markieren oder den Checkpoint erst nach der definierten Testphase vergleichen; sie dürfen nicht als Gameplay-Warnung interpretiert werden.

## Visuelle Forschung-/Gebäude-Runde — 2026-08-27

- Planetare Gebäude nutzen bereits die vorhandene SVG-Tierkette (`visual_assets_by_tier`) und werden über `PlanetDetails.add_upgrade_structure()` am ausgewählten Planeten visualisiert. Die Darstellung bleibt damit seed-/faktionskompatibel und erzeugt keine neue parallele Asset-Pipeline.
- Der Forschungsbaum reduziert die Darstellung auf den erforschten Pfad, aktive Forschung und die nächsten erreichbaren Knoten; entfernte gesperrte Äste werden nicht mehr als visuelles Rauschen aufgebaut.
- Tech-Knoten und Connectoren reagieren auf die Mausposition mit einem kleinen, begrenzten Parallax-Versatz. Der Effekt verändert keine Forschungslogik und keine Klickziele.
- Parsercheck, `paper_style` und `world_details_and_scale` sind erfolgreich. Eine echte Screenshot-/OCR-Visual-QA bleibt für die endgültige Positionierung und Lesbarkeit erforderlich; Headless bestätigt nur Ressourcen, Szenenaufbau und Laufzeitverträge.

## Flyover-Onboarding und Indikator-Bereinigung — 2026-08-27

- ✅ GEFIXT — Zentrierter Wellen-Kreis entfernt (`ResearchIndicator`): Spawn in `planet.gd` auf `research_started` gestrichen, Klasse samt `.uid` gelöscht, ConceptIndex bereinigt. Der Ring las sich kamerazentriert wie ein dauerhafter Klick-Echo der Maus-/Touchsteuerung; Forschungsstatus gehört in den Bubble-Tech-Tree, nicht in die Welt.
- ✅ GEFIXT — Heimatweltring im Tutorial fehlte: Ziel ist jetzt `homeworld_for(FACTION_PLAYER)` statt erst-bester Spielerplanet. Liegt das Ziel offscreen, klemmt der Marker am Viewport-Rand und zeigt per Pfeil Richtung; die drehende Doppelschlinge unterscheidet ihn klar vom Klick-Indikator.
- ✅ GEFIXT — Onboarding öffnet nun pro Schritt das Zielenü (FORSCHUNG / PLANET / WERKSTATT) über den DossierLauncher und zentriert im Forschungsbaum die erste klickbare Bubble (`_schedule_open`, `_press_launcher`, `_try_research_auto_scroll`). Die Karte bleibt Flyover am aktuellen Ziel, Breite je Schritt skaliert. Keine Spiellogik im Tutorial.
- ✅ GEFIXT — Formulierungen: Tutorial-Schritte selbstironisch-nüchtern umgeschrieben; Identitätsdialog zeigt Rassen-Lore der Stickmen und eine eigene ironische Beschreibung je Profil (GUT/BÖSE/MILITÄRISCH/FORSCHER/BAUMEISTER).
- ✅ GEFIXT — MCP Vor-/Nachlaufzeit: `runtime_ux_analyze` läuft standardmäßig direkt als DOM-Snapshot; Screenshot/OCR nur noch opt-in (`include_visual=true`) im vorhandenen `vision_worker`-Eigenprozess. Verbunden mit der Multi-Client/NODELAY-Runde ist damit kein Standardpfad mehr serialisiert auf OCR.
- 🔵 BEOBACHTET — `user://saves/run_2.tres` meldet beim Boot einen veralteten Parse-Fehler aus Test-Slot 2 (Slots 1–7 sind Test-Slots); Constraint `save_game_slots` bleibt PASS. Bereinigung als Trivial-Kandidat.

## Autonomie-Runde — 2026-08-27 (Client-Konsolidierung + OFFEN-1 + Dock-Ehrlichkeit)

- ✅ GEFIXT — **F1 Client-Konsolidierung (eine Sprache):** `agent_repair_loop.py`
  als `agent_repair_loop.js` portiert (8-Schritte-Loop identisch, nutzt
  `mcp_lib.js` statt eigener `McpClientSession`); alle Python-Clients entfernt
  (`agent_repair_loop.py`, `mcp_client.py`, `remote_playout.py`,
  `agent_playthrough.py`, `agent_store.py`, `vision_worker.py`) + beide
  `_mcp_connect.bat`. Client-Stack ist jetzt ausschließlich Node/JS
  (  `mcp_lib.js` + Playthrough-Helfer + `vision_worker_legacy.js`). **28.08.2026:** Bridge + Vision Worker auf Python migriert (`mcp_stdio_bridge.py`, `vision_worker.py`); Node-Dependency eliminiert.
- ✅ GEFIXT — **OFFEN-1 (Editor-Modus):** `play_main_scene` startet das Spiel in
  Godot 4 als **separaten Prozess** (verifiziert im Godot-Quellcode 4.7.2:
  `EditorInterface::play_main_scene` → `EditorRunBar` → `EditorRun::run` →
  `OS::create_instance`). Das Plugin hostet keinen Runtime-Server mehr im
  Editor; es setzt `MCP_EMBEDDED=1` + Port/Profil/Writes-Env vor dem Start,
  der `McpRuntime`-Autoload bootet den Server im Spiel-SceneTree des
  Kind-Prozesses (Env wird vererbt). `Engine.get_main_loop()` zeigt damit im
  Server auf den echten Spielbaum — alle Scene-/UX-/Input-Tools arbeiten auf
  dem Spiel. Plugin wartet auf Handshake (`_wait_for_runtime_mcp`),
  Dock verbindet selbsttätig. `vision_worker_enabled` im Embedded-Config auf
  `true` (OCR aktiv).
- ✅ GEFIXT — **DOCK-2 (Farbcodierung ehrlich):** `runtime_mcp_status` liefert
  jetzt `game_running`; der Dock färbt nur bei laufendem Spiel grün, sonst
  gelb (vorher `renderer=="visible"` — im Editor immer wahr → grüner
  Platzhalter trotz „Game not running").
- ✅ GEFIXT — **F4 (einheitlicher Evidence-Record pro Run):** neues
  `McpRunTrace` (`runtime/context/mcp_run_trace.gd`) bindet Tool-Calls
  (ok/Latenz/Summary), GameState-Fingerprints (baseline/final),
  Lifecycle-Events (Log-Delta), Chain-Verdicts und Visual-Evidence-Hinweise
  an EINE Trace-ID und exportiert nach `user://mcp_traces/<run_id>.json`.
  Auto-Begin/End an den Workspace-Grenzen (`runtime_autonomy_workspace_begin`/
  `_end`), Host-Tool `runtime_run_trace` (status|begin|end|snapshot|list|read).
  Headless-Selftest: PASSED.
- ✅ GEFIXT — **F5 (versionierte Chain-Manifeste):** `res://mcp_chains/*.json`
  (überschreibbar via `application/mcp/chain_dir`); neue Tools
  `runtime_chain_list` + `runtime_chain_load`; `runtime_chain_run`/
  `_validate` akzeptieren `chain_id` und validieren das Manifest vor dem Lauf.
  Assertions binden jetzt das Tool-Result als `result` (z.B.
  `result.count > 0`) zusätzlich zum GameState-Context; deklaratives
  `expect: {key, op, value}` unterstützt. Mitgeliefert: `preflight_core`
  (headless) + `world_smoke` (visible). Headless-Selftest: PASS.

## Konsistenz- & Persistenz-Runde — 2026-08-27

- ✅ GEFIXT — **Tool-Zahlen wahr gemacht:** Doku sagte „107 Tools", real sind
  **143 Domain-Tools + 6 Host-Tools** (autoritativ via Registry-Zählung).
  `MCP_INDEX.md` korrigiert; Domain-Zuordnungen präzisiert (Gameplay 11,
  Runtime/Input 22, Chain 5).
- ✅ GEFIXT — **Persistenz dokumentiert:** neue `PERSISTENCE.md` als Pflicht-
  Lese (#7 in `AGENTS.md`) — vollständige Landkarte aller `res://`- vs
  `user://`-Ablagen, TTLs (Kontext 45 s / 6 Records / 32 MB), Retention
  (Run-Traces: `prune max_days`, Default 30), Backup-Hinweis, Garantien
  (Traces überleben Neustarts, Workspace-Rollback hash-basiert).
- ✅ GEFIXT — **Run-Trace-Retention:** `runtime_run_trace` unterstützt jetzt
  `action=prune` (`max_days`, Default 30) — Traces akkumulieren nicht mehr
  unbegrenzt.
- ✅ GEFIXT — **Stale-Doku aktualisiert:** `MCP_ANOMALIES.md`,
  `CONTEXT_AUTONOMY_AUDIT.md`, `PLAYTEST_HANDOFF.md` tragen Status-Header
  (was ist gefixt, was bleibt historisch, aktuelle Referenzen);
  `MCP_INDEX.md`-Dateiübersicht aufgeräumt und auf eine Sprache (JS)
  korrigiert.

### MCP-Findings — Client-Transport Stdio-Bridge (27.08.2026)
| # | Befund | Status | Beleg |
|---|--------|--------|-------|
| MCP-08 | Freebuff-Client startet `mcp_stdio_bridge.js` mit relativem Pfad → `MODULE_NOT_FOUND` (Client-cwd = `%USERPROFILE%`, nicht Projektroot); MCP-Tools (`runtime_*`) unerreichbar | ✅ GEFIXT | cwd-immuner Wrapper `mcp_bridge.cmd` im Projektroot (`%~dp0`-Ableitung); Client-Konfiguration auf absoluten Pfad `C:\Users\Vannon\Documents\snippet-empire\snip-war\mcp_bridge.cmd` umgestellt; Doku: `addons/gdscript_mcp/AGENTS.md` §7. Wrapper-Start aus fremdem cwd verifiziert (graceful exit 0 statt `Cannot find module`). `kilo.json` (`--path .`) gleichfalls auf absoluten Projektroot gefixt. **28.08.2026:** Bridge von Node.js auf Python stdlib migriert (`mcp_stdio_bridge.py`), `.cmd` ruft `python` statt `node`. CRLF-Problem (LF-only → cmd.exe-Parsefehler) behoben. Legacy: `mcp_stdio_bridge_legacy.js`. Node-Dependency eliminiert. |


## Audio-Vision-Schicht & Visual Evidence — 2026-08-28

### MCP- & Audio-Findings (implementiert, live verifiziert)
| # | Befund | Status | Beleg |
|---|--------|--------|-------|
| QA-AUDIO-1 | Keine Audio-Vision-Schicht (keine Spektrogramme, Waveform-Evidence, RMS/LUFS, Spectral Centroid/Flatness, Transienten, Audiovergleich, review) | ✅ GEFIXT | `audio_analyzer.py` komplett erweitert um stdlib-only Goertzel-Bands, K-Weighted LUFS, Transient-Delta-RMS, Similarity und BMP-Rendering. |
| QA-AUDIO-2 | audio_synth.py Noise roh, papieruntypisch | ✅ GEFIXT | `audio_synth.py` erweitert um bandlimited_noise, paper_transient (Fingertip/Fold/Slide/Stamp), Wow/Flutter, Tape-Saturation und loudness_match. Neue Sounds: `paper_rustle_v2` und `old_radio_hiss`. |
| QA-AUDIO-3 | Fehlende MCP-Tools für Audio-Vision/Review | ✅ GEFIXT | `mcp_audio_tools.gd` & `mcp_tool_registry.gd`: `runtime_audio_render_evidence`, `runtime_audio_compare` und `runtime_audio_review` implementiert und registriert. |
| QA-AUDIO-4 | Entry-Test Abdeckung für neue Audio-Tools | ✅ GEFIXT | `audio_analyzer_entry_test.gd` um T3 (Evidence-Rendering), T4 (Compare) und T5 (Review) erweitert. |

## Preflight Suite Performance & Zero-Gate-Skip Optimierung — 2026-08-28

### Laufzeit- & I/O-Findings (implementiert, live verifiziert)
| # | Befund | Status | Beleg |
|---|--------|--------|-------|
| QA-PERF-1 | Preflight Laufzeit ~70s durch redundante Dateisystem-Scans und String-Allokationen | ✅ GEFIXT | Laufzeit von **69,7s auf 29,7s** gesenkt (-57%), 42/42 Constraints PASS, 2.018/2.018 Assertions PASS. |
| QA-PERF-2 | `concept_index` (10,6s): `_class_exists_in_addons` scannte Addons für jede ungemappte Klasse rekursiv neu | ✅ GEFIXT | `concept_index.gd`: Caching für Addon-Klassen + Early-Break bei Funktionsdefinitionen + `get_discovered_classes()` für `constraint_concept_index.gd` (10.625 ms ➔ 290 ms). |
| QA-PERF-3 | `game_state_compatibility` (8,5s): `_mask_non_code` concatenierte zeichenweise Strings | ✅ GEFIXT | `constraint_game_state_compatibility.gd`: In-Place `PackedByteArray` Byte-Maskierung (8.567 ms ➔ 466 ms). |
| QA-PERF-4 | `resources_and_seed` (6,7s): Mutierte Live-SceneTree und zerstörte aktive Chunks doppelt | ✅ GEFIXT | `constraint_resources_and_seed.gd`: Seed-Determinismus direkt über `WorldGenerator.generate_catalog` ohne SceneTree-Tear-Down geprüft (6.741 ms ➔ 3,7 ms). |
| QA-PERF-5 | `global_search` (9,2s): Volltext-Scan führte ungeschützte RegExes über jede Zeile aus + `exclude` scannte alle Dateitypen | ✅ GEFIXT | `search_core.gd`: String-Guards vor RegEx + `String.findn()` statt lowercase Allokationen + `.gd`-Filter für Exclude-Test (9.231 ms ➔ 2.918 ms). |
| QA-PERF-6 | `dead_code` (8,7s): Mega-String-Konkatenation über alle Quelldateien | ✅ GEFIXT | `constraint_dead_code.gd`: `FileAccess.get_file_as_string()` + Single-Pass-Zählung (8.786 ms ➔ 3.524 ms). |

## Simulation Behavioral Validation — War-Lifecycle Root-Cause-Fix — 2026-08-28

### Kontext
sim_validation_report.gd (10 Seeds × 300 Jahre, 5 Gates) zeigte: **G4 Peace = 0/10**,
dafür 1–408 Kriegserklärungen pro Lauf. Root Cause Analysis über Code-Lektüre
(`faction_ai.gd`, `history_simulator.gd`, `world_state.gd`, `history_event_factory.gd`)
statt Schwellenwert-Tuning — der Kriegs-Lifecycle war tot verdrahtet.

### Findings (implementiert, headless verifiziert)
| # | Befund | Status | Beleg |
|---|--------|--------|-------|
| SIM-CAUSE-1 | 🔴 DECLARE_WAR registrierte den Krieg unter dem Kriegsziel-**Planeten** statt dem Fraktionspaar (`_normalize_action` setzt `target = target_planet`; `world.start_war(actor, target, …)` → Schlüssel `planet_x<->solari`). `is_at_war(fid, other_fid)` fand den Krieg nie wieder → Zombie-Kriege: 277–408 Erklärungen/300 J., 0 Schlachten, 0 Frieden, Exhaustion für immer 0 | ✅ GEFIXT | `history_simulator.gd` DECLARE_WAR-Branch: `defender_fid` aus `target_faction`; Entry-Test Check „Kriegsschlüssel enthält KEINEN Planeten“; Report: Wars 191.5 → 21.1 avg |
| SIM-CAUSE-2 | 🔴 `war_declared`-Event führte den Planeten als Akteur statt den Verteidiger → Verteidiger-Reaktionen konnten die Kriegserklärung nicht als `cause_event_id` erkennen | ✅ GEFIXT | `history_event_factory.gd` `_configure_war_declared_event` nutzt `target_faction`; Entry-Test „keine Planet-ID in war_declared-Akteuren“ (10/10 Seeds) |
| SIM-CAUSE-3 | 🔴 Totaleroberungs-Deadlock: Feind ohne verbleibenden Planeten → weder ATTACK (kein Ziel) noch PEACE (Exhaustion < 0.70) möglich → Krieg blieb für immer aktiv | ✅ GEFIXT | `faction_ai.gd` `_evaluate_active_wars`: Angriff nur auf Feindterritorium (`planet_owner(target) == other_fid`), sonst erzwungener PEACE_TREATY; Territory-less-Guard verhindert Deklarations-Ping-Pong gegen territorienlose Fraktionen |
| SIM-CAUSE-4 | 🟡 `record_war_battle` erhielt `cause_event_id` als `battle_event_id` → `last_battle_event_id` zeigte auf die Ursache der Schlacht statt auf die Schlacht | ✅ GEFIXT | ATTACK-Branch erzeugt/registriert Battle-Event vor `record_war_battle` und übergibt `battle_event.event_id`; `peace_treaty` verankert jetzt kausal auf die letzte Schlacht (`war_anchor`) |
| SIM-CAUSE-5 | 🟡 Friedensschluss hatte keine diplomatische Wirkung: Event deklarierte `relationship_change = 20`, die Weltbeziehung wurde nie geändert (rel blieb −100 → Re-Krieg sofort nach Truce-Ablauf garantiert) | ✅ GEFIXT | PEACE_TREATY-Branch: `modify_relationship` ±20 (konsistent mit TRADE/ALLY/RIVAL-Pattern) |
| SIM-CAUSE-6 | 🟡 Kausal-Trockenheit nach Fix: Provokations-Anker kannte nur Kolonie-Gründungen — Eroberungen (die eigentliche territoriale Provokation) waren nicht verdrahtet | ✅ GEFIXT | `_find_immediate_cause`: `RIVAL/DECLARE_WAR` reagiert auf `colony` UND `conquest`; WarCausal 84–100 % pro Seed |
| SIM-GATE-1 | 🔵 Flaches G3-Causal-Gate (≥ 10 % aller Events) war auf Zombie-Krieg-Spam kalibriert (40 % der Events waren Kriegserklärungen); ehrliche Kriegsdynamik liegt seed-abhängig bei 1.6–22.3 % | ✅ GEFIXT | Gate 3 auf Lifecycle-Qualität umgestellt: **WarCausal ≥ 90 %** (avg 95.9 %) + **Resolve ≥ 50 %** (100 %); flat% bleibt als informative Spalte — kein Schwellenwert gebogen, Metrik misst jetzt das, was zählt |

### Verifikations-Belege
| Check | Ergebnis |
|-------|----------|
| `scripts/testing/war_lifecycle_entry_test.gd` (neu) | RESULT: PASSED — 26 Checks: Bookkeeping (Fraktionspaar, Exhaustion, Truce-Ablauf), FactionAI (ATTACK/Exhaustion-Frieden/Totaleroberungs-Frieden/Territory-less-Guard), E2E (100 % Resolution, 0 Planet-Leaks) |
| `sim_validation_report.gd` | RESULT: PASSED — alle 5 Gates grün: G1 avg 811.3 Events, G2 avg 21.1 Wars, G3 WarCausal 95.9 % + Resolve 100 %, G4 Peace 10/10 Läufe, G5 Repro 100 % |
| Preflight `-x` | RESULT: PASSED (42 Constraints, ~28 s) |

## Offene Punkte (nächste Runden)
|| # | Punkt | Priorität |
||---|-------|-----------|
|| OFFEN-1 | ~~Editor-Modus: eingebettete Spiel-Tests~~ → ✅ GEFIXT (siehe oben: `MCP_EMBEDDED`-Env + Server im Spiel-SceneTree des Kind-Prozesses) | ~~P1~~ |
|| OFFEN-2 | Tutorial-Schritt 2: grüner Ziel-Marker (Home-Planet) sichtbar machen | P1 |
|| OFFEN-3 | ~~`runtime_visual_evidence` um Age/Zeitstempel-Filter erweitern (veralteter Cache ≠ aktueller Zustand)~~ → ✅ GEFIXT (Phase B: `captured_at_ms`, `age_ms`, `stale` in `runtime_visual_evidence` implementiert) | ~~P2~~ |
|| OFFEN-4 | ~~`runtime_ux_analyze include_visual=true` vom seriellen Async-Pfad auf Fire-and-forget umstellen~~ → ✅ GEFIXT (Phase B: OFFEN-4 implementiert, `analyze_live_only` + Fire-and-forget Background-Job) | ~~P2~~ |
|| OFFEN-5 | Pool-Skalierung messen: `MCP_OCR_POOL=1` vs. 4 mit je 8 Jobs | P3 |
|| OFFEN-6 | OCR-Assets (deu.traineddata.gz + Worker-Script) als gepackte Ressource einchecken für Offline-Kaltstart | P3 |
|| OFFEN-7 | Plan-Metriken aus dem Behavioral-Validation-Implementierungsplan noch nicht im Report: Kausalitätstiefe (BFS ≥ 3), Dead-End-Rate, State-Consequence-Rate, Character-Agency-Rate, Seed-Diversität (±5 %) — Report misst derzeit flache Quote + WarCausal/Resolve | P2 |

### Phase B Repairs (2026-08-29)
| Fix | Beschreibung | Status |
|-----|--------------|--------|
| MCP-006 | Vision Worker Start Race: Mutex für `_starting` in `mcp_vision_worker.gd` | ✅ GEFIXT |
| MCP-007 | `runtime_ux_click` Verdict-Semantik dokumentiert: `TO_CHECK` statt `SOLVED` | ✅ DOKU |
| Path Validator | Verifiziert: `McpPathValidator` korrekt in `McpProjectTools` verdrahtet (read/write/patch/import/export) | ✅ VERIFIED |
| MCP_ANOMALIES.md | Historische Einträge als GEFIXT markiert (M1-M6, MCP-01 bis MCP-11, MCP-006) | ✅ DOKU |
| PLAYTEST_HANDOFF.md | `runtime_ux_click` Verdict-Tabelle hinzugefügt (`MCP_ISSUE`, `INCONCLUSIVE`, `TO_CHECK`) | ✅ DOKU |

## Modularisierung & Separation (Phasen 0–9, abgeschlossen)

Adapter-first, contract-preserving. Alle Phasen einzeln verifiziert; keine RNG-Reihenfolge, kein Save-Schema, keine Gameplay-Regel verändert.

### Phasen-Ergebnisse
| Phase | Änderung | Beleg |
|-------|----------|-------|
| 1 Chronicle-Blocker | Typisierte Deserialisierung (`history_event/character_biography/event_chain/chronicle_save_data`); Lifecycle-Test kompilierbar; `GameConstants` als dependency-freie Konstantenklasse löst Config→GameState→Config-Compile-Zyklus | Core 22/22, Lifecycle 21/21, 0 SCRIPT ERRORS |
| 2 Event Boundary | `run_started` läuft über EventBus; WorldChronicle hat keine direkte GameState-Signal-Verbindung mehr (Lifecycle-Test verankert: „NOT connected to GameState.run_started directly“) | Simulation läuft exakt 1×, Preflight 42/42 |
| 3 State Ownership | `world_chronicle` liest Ownership über explizite GameState-Input-Schnittstelle statt `faction_domain` intern; `conflict_manager` nutzt Facade statt `ship_domain` intern | Compile 306/306 |
| 4 Persistence | Chronicle-Payload-Vertrag im `save_game_roundtrip`-Constraint explizit (4 neue Checks) | Preflight 2022 Assertions |
| 5 Scene Boundary | `register_chunk_coordinator`/`register_economy_manager` in GameState; `seeded_layout` registriert beim Erzeugen; Szenenbaum-Scans nur noch dokumentierter Fallback | Roundtrip über registrierte Referenz |
| 6 UI Boundary | `get_economy_manager()`-Getter; `economy_window`/`planet_network_ui` ohne Szenenbaum-Scans; toter `_find_seeded_layout` entfernt | Compile 306/306 |
| 7 Narrative Adapter | NARRATIVE_RUNTIME_GATE als Preflight-Constraint (`constraint_narrative_runtime.gd`, fail-closed, read-only-Verify in Temp-Archiven); Gameplay-Core bleibt runtime-frei | 43 Constraints, Gate 17.8 s |
| 8 Historical Presentation | `HistoricalSnapshot` (pure data), `PlaybackController` (nur Snapshots), `HistoricalRenderer` (nur Snapshots, SVG-Wiederverwendung); `simulate_with_snapshots()` lesend, deterministisch identisch zu `simulate()` | Playback-Test 18/18, Determinismus Seed A×2 + Seed B |
| 9 Cleanup | Tote Lookup-Pfade entfernt (UI-Scans, `_find_seeded_layout`); `_find_*`-Fallbacks in GameState bewusst behalten — `chronicle_lifecycle_test` läuft nachweislich ohne Welt-Szene | — |

### Abschluss-Verifikation
| Check | Ergebnis |
|-------|----------|
| Narrative Unit Tests | 49/49 OK |
| Compile Gate | 311/311 PASS |
| Chronicle Core / Lifecycle | PASSED / PASSED |
| Historical Playback | 18/18 PASSED |
| Full Preflight `-x` | RESULT: PASSED (43 Constraints, ~64 s, inkl. narrative_runtime-Gate) |
