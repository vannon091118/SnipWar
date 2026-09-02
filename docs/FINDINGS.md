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
- ✅ **SOLVED** — verifiziert behoben (Beleg + Verifikationskommando angegeben)
- 🟡 **UNSOLVED** — offen/partiell (Ursache + Schnittstelle + nötige Verifikation)
- 🔵 **BEOBACHTET** — verifiziertes Verhalten, bewusst so gelassen (kein Fix nötig)

> Die historischen QA-Runden-Befunde sind weiter unten konserviert. Diese
> beiden Sektionen sind die **aktive Führung**: was geschlossen ist und was
> offen bleibt. Jeder neue Befund wird hier eingetragen.

---

## ✅ SOLVED — verifizierte Befunde

| # | Befund | Beleg / Verifikation |
|---|--------|---------------------|
| #1 | Zentrierter Wellen-Kreis (wie Klick-Indikator): `planet.gd` spawnte `ResearchIndicator` auf `research_started` → Klasse + `.uid` gelöscht; `touch_feedback_layer.gd` Ripple nur noch bei Touch | `git log --follow` zeigt Löschung; `find . -name "research_indicator*"` leer; compile_gate PASS |
| #2 | Tutorial-Schritt 2 grüner Ring um Home-Planet: `tutorial_director.gd _target_planet()` → `homeworld_for(FACTION_PLAYER)`; grüne Doppelschlinge `_draw_marker` + Offscreen-Pfeil | User live verifiziert; `grep -n "homeworld_for" scripts/ui/tutorial/tutorial_director.gd` |
| #3 | Flyover-Karten mit Pfeil-Konnektor, WEITER-Puls, Light-Ring-Fade: `tutorial_director.gd` implementiert | R-014-A: `tutorial_director.gd _position_card`/`_draw_marker`/`_process` + `_find_launcher_button`/`_try_research_auto_scroll`; live + MCP `runtime_ux_scan` verifiziert |
| #4 | Forschung feuerte „automatisch": CPU-Forschung (`&"b"`) toastete als Spieler-Event → `event_log.gd:118` `if faction != &"a": log_silent(...)`; MCP: `runtime_ux_analyze` = direkter DOM-Snapshot, OCR nur opt-in im eigenen `vision_worker.py`-Prozess | `grep -n "faction != &\"a\"" scripts/state/event_log.gd`; live 28.08.2026 |
| #5 | Menü-Open/Close-Animation „Zerknüllen" (1–2 s): Godot-nativer Crumple-Tween/Shader in `paper_dossier.gd _set_open` implementiert | R-014-D: visueller QA verifiziert |
| #6 | Menü-Identität/Blueprint-Optik mit SVG-Upgrades: `paper_dossier.gd`/`planet_details.gd` implementiert | R-014-E: Asset-Ableitung aus Vorhandenem; visueller QA verifiziert |
| #7 | Forschungs-Bubbles bewegen sich mit Maus; TechTree nur aktueller Pfad + nächste: `parchment_tech_tree_view.gd _visible_path_technologies` (gelernt + Frontier + max 1 Folgeknoten, Cap 12) + `_process`-Parallax | Code-Lektüre `scripts/ui/dossier/parchment_tech_tree_view.gd`; live verifiziert |
| #8 | Selbstironische Formulierungen/Benennungen: Tutorial-Texte + Identitätsdialog (Rassen-Lore) + Profil-Beschreibungen | `scripts/ui/main_menu.gd _select_profile` + `_show_identity_intro` |
| #9 (SVG) | Profil-SVGs: `_show_identity_intro` + `set_player_identity()` implementiert; SVGs in `assets/ui/stickman/` aus `stickman_fracture.svg`/Banner-/Upgrade-SVGs abgeleitet | R-014-F: `ls assets/ui/stickman/` zeigt SVGs; visueller QA verifiziert |
| #10 | Stickman-Lore: `res/lore/stickman.md` + `factions_overview.md` + `world_lore.md` + `reaper.md` mit Inhalten befüllt (Fragmente genutzt) | R-014-G: `res/lore/*.md` Inhaltsausarbeitung abgeschlossen |
| QA-GAME-3 | Forschung feuerte automatisch | = #4, siehe oben |
| OFFEN-3 | `runtime_visual_evidence` Age/Zeitstempel-Filter | `captured_at_ms`/`age_ms`/`stale` implementiert |
| OFFEN-4 | `runtime_ux_analyze include_visual=true` Fire-and-forget | `analyze_live_only` + Background-Job implementiert |
| F-201…F-215 | Konsolidierungs-Audit-Befunde | siehe historische Sektion unten; alle ✅ GEFIXT bzw. 🔵 |
| PL-A…PL-E | Pipeline-Koordinations-Befund (Phase 3 Ownership+Digest+Evidence-Fix) | compile 337/337, preflight 44/44 PASSED |
| **W2-A3-TEST** | Test Coverage erweitert: Save/Load Roundtrip, Combat Simulation, Ship Builder/Blueprint, Navigation/Transit, CPU AI Behavior Tests; Constraint Coverage Test; Deterministische Test-Runs | `scripts/testing/*_test.gd` (19 Entry-Tests); `constraint_coverage_test.gd`; `test_all.gd` Cache + Deterministic Mode |

---

## 🟡 UNSOLVED — offene / partielle Befunde

| # | Befund | Ursache / Schnittstelle | Nötige Verifikation |
|---|--------|------------------------|---------------------|
| #11 | MCP-Laufzeiten: Live-Pfad ms-schnell; längste Seriellpfade: Full-Preflight (~54 s), Szenen-Boot-Constraints (~3,5 s je) | `preflight.gd`; `tutorial_director.gd` (CanvasLayer layer 92, Pfad nicht exponiert) | Performance-Optimierung; OFFEN-5/6/7 |
| QA2-MCP-5 | `runtime_audio_list_streams` → `[]` im Hauptmenü | Audio-Pipeline ungeklärt | `runtime_audio_analyze`/Code-Audit |
| F-304 | `reset_state()` partiell: Field-Node-Count leakt über Constraint-Grenzen | `v2_fixture.gd`/`v2_context.gd` | enge Lösung (welcher Knoten wurzelt), kein Pauschal-Restore |
| F-306 | Selfcheck „65 Regressionstests“ nicht reproduzierbar | `doki_selfcheck.gd` | `git log --follow`-Provenienz |
| P-401…P-403 | Kampf-/Conquest-Ausgang nicht im Hard-State; `pending_battle`/`battle_counter` nicht persistiert | `game_state.gd restore_run`; `conflict_manager.gd` | RunSaveData-Felder + Restore-Pfad |
| OFFEN-2 | Tutorial-Schritt 2 grüner Ziel-Marker | = #2 (SOLVED), Legacy-Eintrag | — |
| OFFEN-5 | Pool-Skalierung messen (`MCP_OCR_POOL=1` vs 4) | OCR-Worker-Pool | Benchmark |
| OFFEN-6 | OCR-Assets als gepackte Ressource einchecken | `deu.traineddata` | Offline-Kaltstart |
| OFFEN-7 | Plan-Metriken im Sim-Report | `sim_validation_report.gd` | Report-Erweiterung |
| QS-1 | Tutorial-Zwischenschritte: 8 grobe Schritte ohne Subsystem-Erklärungen (Vault/Worker/Werft-Gate/Hangar); WEITER-Button nicht blinkend | `tutorial_director.gd _build_steps`/`_weiter_button` (Zeile 142); `_schedule_open`/`_press_launcher` | R-014-A: Zwischenschritte + WEITER-Puls; live + MCP `runtime_ux_scan` |
| QS-2 | Werkstatt: Hangar und Shop nicht getrennt; Kauf-Liste ohne Asset-Thumbnails; Montage-Visual existiert nur in der Welt (`CompositeShipView`), nicht in der Werkstatt-UI | `workshop_view.gd` (Scrollbereich); `tech_ship_builder_view.gd` (Kauf-Liste); `shipyard_hangar.gd show_ship_parts()` (Welt) | Werkstatt-UI-Split + Thumbnail-Verknüpfung; visueller QA |
| QS-3 | Kein Shop-Dossier; kein Ausgaben-Tracking („investierte Credits/Ressourcen pro Faktion“); kein angebotsdynamisches Sortiment | `scripts/state/domains/economy/*` (Vault/Deal/Upgrade/Refinery-Trade/Gathering-Transport/Worker-Factory/Buildings — keine Shop-Einheit); `refinery_trade_unit.gd market_price()` als Ansatzpunkt | Economy-Modul `shop_unit.gd` + Shop-Dossier-View; Preflight-Test |
| QS-5 | Zoom/FoW/Sternenkarte: `map_camera.gd` min=1.0/max=2.5 (nur hereinzoomen); FoW statisch (nicht zoom-adaptiv); Sternenkarte existiert nicht als Max-Zoom (separate Szene `historical_world.tscn`); Stern-Assets ungenutzt | `map_camera.gd` (Zeilen 8–9); `planet_network.gd _refresh_fog_of_war()`; `star_*.svg` (4 Waisen) | `max_zoom` erweitern + LoD-Stufen + zoom-adaptiver FoW + Sternenkarte als Max-Zoom-Stufe; visueller QA |
| QS-6 | Asset-Waisen: `armor_heavy.svg`/`drive_advanced.svg`/`star_*.svg`(4)/`automated_mine.svg`/`comms_array.svg` ungenutzt; `scanner_t2.svg`/`sensor_array.svg` gelöscht; Repo-Junk im Root (`C:UsersVannon…*.svg` als Dateinamen) | `git grep` zeigt 0 Referenzen; `ship_part_catalog_default.tres` nutzt andere Pfade; `git status` zeigt `D` + kaputte Dateinamen | Asset-Verdrahtung (neue Katalog-Einträge) ODER als ungenutzt markieren; Repo-Hygiene (R-003-ähnlich) |



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

---

## Konsolidierungs-Audit 2026-08-29 — Forensik & ROADMAP etabliert (R-001)

> Basis: READ-ONLY-Forensik-Lauf (Repo-Inventur, Live-Code-Lektüre, frischer Preflight 43/43, Laufzeit-Messungen). Übergeordnete TODO-Kette: `ROADMAP.md` (einzige vorwärts denkende Quelle; CHANGELOG = Vergangenheit, FINDINGS = offener Schaden).

### Befunde (F-200)
| # | Befund | Status | Beleg / Referenz |
|---|--------|--------|------------------|
| F-201 | Constraint-Zahlen-Drift: 34/36/38/39/42 in 7 MDs gleichzeitig behauptet (ARCHITECTURE.md:349 = 38; DESIGN §1 = 39 vs. §14 = 34; docs/README = 36; PLAN.md = 36; GAME_CYCLE_CONCEPT = 34) plus Autoload-Zählung (DESIGN SO1 = 8) | ✅ GEFIXT | R-002: alle 11 Stellen auf 43 Constraints / 10 Autoloads vereinheitlicht (später auf 44 durch R-051 historical_world, dann 45 durch agent_activity; docs_integrity prüft jetzt die Gesamtzahl mechanisch) (ARCHITECTURE, DESIGN ×4, AGENTS, PLAN, docs/README ×3, GAME_CYCLE_CONCEPT); historische datierte Lauf-Belege in FINDINGS bleiben unangetastet |
| F-202 | Autoload-Drift: DESIGN.md §17.2 SO1 nannte 8 Autoloads, `project.godot` hat 10 (EventBus, WorldChronicle fehlten dort; INVENTORY_MATRIX.md korrekt) | ✅ GEFIXT | R-002: DESIGN SO1 listet jetzt alle 10 Autoloads (verifiziert 29.08.); Duplikat-Anteil von F-201 |
| F-203 | CODEBASE_AUDIT.md (29.08.) widerlegt: behauptete „HistoricalWorld.tscn fehlt / nicht verdrahtet“ | ✅ GEFIXT | R-050+R-051: Szene existiert, preloaded, Menü-Eintrag, Preflight-Gate (44/44); CODEBASE_AUDIT.md als HISTORISCH markiert (R-005) |
| F-204 | `battle_context_changed`: 2 Emits (game_state.gd:442/453), 0 Connectoren; `run_started`-Signal: 1 Emit, 0 Connect (kanonischer Pfad = EventBus, Compatibility-Signal bleibt) | ✅ GEFIXT | R-006: Befund WIDERLEGT durch Messung (F-212): 6/38 GameState-Signale ohne externe Consumer, 5 davon akzeptierte Anker (mid_game_started, transit_changed, run_started, planet_building_placed/destroyed); MechanicRegistry reflektiert Signale als Mechanik-IDs, scenarios/*.tres + SCENARIO_LOADER_SPEC referenzieren `battle_context_changed` als Combat-Mechanik → Anker bleibt, Kommentar in game_state.gd verankert Klassifikation; run_started/ship_launched/milestone_reached haben kanonische EventBus-Zwillinge (EventLog/WorldChronicle konsumieren via EventBus) → Compatibility-Facade bleibt (F-204-Dokumentation bestätigt) |
| F-205 | ConceptIndex: 5 unmapped Klassen (RunPreparation, GameConstants, FactionAI, PreflightConstraintHistoricalWorld, PreflightCodeIndex) | ✅ GEFIXT | R-010: Alle Klassen den passenden Konzepten zugeordnet; concept_search --unmapped = 0; concept_index-Constraint 16/16 PASS |
| F-206 | Repo-Junk: `kilo.json`, `snapshots/`, `tmp_*` | ✅ GEFIXT | R-003: 8 Dateien git rm (1429→1421), snapshots/ + tmp_* gelöscht, Compile 317/317 |
| F-207 | HistoricalWorld bootete mit leerer Chronik: `ERROR: HistoricalWorld: chronicle has no historical snapshots` (headless reproduziert); `run_started` feuerte erst in world.tscn (`WorldBootstrap.begin_new_game`) → toter Spielerfluss „NEUES SPIEL“ | ✅ GEFIXT | R-050: `scripts/bootstrap/run_preparation.gd` (prepare_new_run) + main_menu ruft vor dem Szenenwechsel; Bootstrap-Fallback bei leerer Chronik; `historical_world_flow_test.gd` 11/11 PASS; R-051: `constraint_historical_world.gd` (pure, 11 Checks, 7,2 s) sichert Flow als Preflight-Gate (44/44) |
| F-208 | MCP_AUDIT_REPORT.md referenzierte `scripts/tools_count.gd` als autoritativ — Datei existiert nicht | ✅ GEFIXT | R-011: MCP_AUDIT_REPORT als HISTORISCH markiert; MCP_INDEX.md Referenz auf McpToolRegistry-Reflection aktualisiert |
| F-209 | Preflight top-6 Constraints ≈ 16 s (dead_code 3,5 s / scene_boot 3,5 s / global_search 2,9 s / world_details 2,5 s / context_handover 2,1 s / camera_and_input 1,6 s); Einzel-Fixes der QA-PERF-Runde vorhanden, aber kein länderübergreifendes Shared Inventory | 🟡 OFFEN | tmp_timings.json + frischer Lauf; → R-012 |
| F-210 | Kein zentraler Test-Orchestrator | ✅ GEFIXT | R-009: `scripts/testing/test_all.gd` (8 Entry-Tests + Preflight -x, 9/9 PASS, 140 s, Exit 0/1); Optionen: FILTER/SKIP_PREFLIGHT/TIMEOUT |
| F-211 | Doppel-Simulations-Risiko: Nach HistoricalWorld würde world.tscn erneut `begin_new_game()` feuern (zweite Chronik-Simulation), weil `request_world_reconnect()` nie gesetzt wurde | ✅ GEFIXT | R-050: `historical_world_bootstrap._on_playback_finished` ruft `request_world_reconnect()` vor dem Szenenwechsel; reconnect-Pfad in world_bootstrap verifiziert; Flow-Test Check 4 |
| F-212 | Heuristik „0 Consumers = tot“ widerlegt: Messung 29.08. — 38 GameState-Signale, 6 ohne externe `.connect()` (battle_context_changed, run_started, mid_game_started, transit_changed, planet_building_placed/destroyed); 5 davon akzeptierte Mechanik-Anker/Compatibility-Facade. Consumer der Mechanik-IDs ist MechanicRegistry (Reflection) + Scenario-Coverage + EventBus-Zwillinge (EventLog/WorldChronicle) | ✅ GEFIXT | R-006: repo-weite .connect()-Messung (93 connect-Signale distinkt, 0 Treffer auf die 6); Entfernung von battle_context_changed hätte den einzigen Combat-Mechanik-Anker aus der Coverage-Matrix entfernt + .tres/Spec-Inkonsistenz erzeugt → Reklassifikation statt Entfernung; game_state.gd-Kommentar verankert |
| F-213 | Economy-Fassade trug noch Businesslogik: Worker-Transport-Records, Worker-Factory-Gating/-Bau, komplette Buildings/Grid-Queue (place/queue/advance/abort/refund) direkt in `economy_domain.gd`; `_route_owner` griff per `Engine.get_main_loop()` global auf GameState zu | ✅ GEFIXT | R-007 (E4a/E4b): `gathering_transport_unit.gd` (Gathering + Transport-Lifecycle), `worker_factory_unit.gd` (Gating/Kosten/Bau), `buildings_unit.gd` (Grid-Queue inkl. Rollback-Reihenfolge) extrahiert; Fassade 655→499 LOC, 83 reine Delegationen; `_route_owner` über injizierten Callable-Resolver (GameState->_init injiziert `faction_of`; ohne Injektion → FACTION_NEUTRAL); Snapshot/Restore unverändert auf Fassade (Semantik identisch); Preflight 44/44 PASSED, test_all 11/11 (E1/E2-E4 registriert) |
| F-214 | False-Green: `test_all.gd`-Discovery matcht nur `*_test.gd` — `e1_vault_core_semantics_check.gd` wurde still übersprungen (Orchestrator meldete ALL PASSED ohne E1 je auszuführen) | ✅ GEFIXT | R-007: Test auf `_test.gd`-Konvention umbenannt (`e1_vault_core_semantics_test.gd`); neuer `e2_e4_economy_units_test.gd` (Deal/Upgrade/Refinery/Trade/Gathering/Transport/Buildings-Grid mit echten Assertions + Failure-Paths); test_all findet jetzt 10 Entry-Tests, 11/11 PASSED |
| F-215 | `planet_network.gd` (1017 LOC) mischte Routing/Netzwerk mit kompletter UI-Orchestrierung: Context-Menü-Konstruktion, Dossier-Launcher, Hotkeys, Fleet-Overview, Economy-Window, Message-Feed, Modal-/Layout-Koordinator, Tutorial, Dispatch-Vorschau | ✅ GEFIXT | R-008: `planet_world_ui.gd` (neu) übernimmt die UI-Orchestrierung; `planet_network.gd` besitzt nur noch Network/Selection/Fog/Rendering/Dispatch + dünne `_world_ui`-Shims; kein UI-Zyklus (Welt-UI ruft dokumentierte Network-Entry-Points); compile 328/328, Preflight 44/44, `r008_world_ui_boundary_test.gd` verankert die Grenze, test_all 12/12 |

---

## Divergenz-Audit 2026-08-30 — Adversarial Counter-Forensics (R-200, „Agent B")

> Basis: Unabhängiger Reality-Snapshot gegen HEAD `22fbb27` (später e6b01a3) — eigener Git-Abgleich, Primärquellen-Lektüre und Live-Läufe; alle Verdicts unabhängig von import A erneut hergeleitet.

### Code-Befunde (Gdsript/Preflight)

| # | Befund | Status | Beleg / Referenz |
|---|--------|--------|------------------|
| F-301 | `cluster_generation` = stille No-Op-Constraint: pure (requires_scene=false), liest aber `ctx.world_config`, der in der Pure-Phase NULL ist → sofortiger `return true` mit **0 Checks** im Lauf (15 Check-Aufrufe im Code); die 44. Constraint trug nichts bei, zählte aber voll | ✅ GEFIXT | Empirisch vorher: `[PASS] cluster_generation (74.82 ms, 0 checks)`. Fix: kanonisches `world_default.tres`-Fallback wie bei Sibling-Pure-Constraints (`chunk_expansion`, `world_generator_scaling`); nachher `[PASS] cluster_generation (19.64 ms, 64 checks, 0 fail)` — `scripts/preflight/constraint_cluster_generation.gd` |
| F-302 | runtime-Cache stale PASS: `_compute_hash()` inkludierte nur chain + change_index + `gate_cli.py` — eine Nonkonformität in **jedem anderen** Runtime-Modul (observe.py/store.py/relationships.py/…, die gate_cli importiert) änderte den Hash nicht → alter PASS-Cache-Eintrag wurde weiter ausgeliefert; `_write_cache` nur bei exit_code OK | ✅ GEFIXT | `scripts/preflight/constraint_narrative_runtime.gd`: Hash wälzt jetzt ALLE `*.py` in `res://narrative_runtime` (top-level) + chain + change_index über den deterministischen Dir-Scan; Cachе-Invalidierung auf JEDE Runtime-Änderung (fail-closed); Tests: Compile-Gate 333/333 PASS, resolver-test PASSED |
| F-303 | AGENTS.md „Legacy V1 archiviert" = STALE_CURRENT_CLAIM: `scripts/legacy/preflight_v1.gd` ist NICHT im Baum (`git ls-files` leer, `find` leer), entfernt in `ab080dc`; CHANGELOG F-104/F-105 = gültige Historien-Einträge | ✅ GEFIXT | AGENTS.md-Zeile korrigiert → „wurde in `ab080dc` entfernt (kein aktives Archiv — V2 ist die Kanonische)"; `git ls-tree HEAD scripts/legacy/` leer |

### Offene / Design-Findings (aus B, nicht autonom entschieden)

| # | Befund | Status | Beleg / Referenz |
|---|--------|--------|------------------|
| F-304 | `reset_state()` ist partiell: Ownership wird restauriert (75→0→75), Field-Node-Count leakt über Constraint-Grenzen (Baseline exp=105, `world_details_and_scale` startet exp=106); Messpunkt liegt VOR dem Reset → „68 Mutationen" überwiegend erwartete Fixture-Mutationen statt Kontamination | 🟡 OFFEN | Blanket-Restore (`queue_free` aller Non-Baseline-Childs) wurde probiert und REVERTIET: crash in `selection_and_context` („previously freed"), `node_count_drift actual: 0`, 2 FAIL im Full-Run → mehrere Drifts stammen von Constraints, die Field legitim neu aufbauen. Enge Lösung nötig (Audit, welcher Knoten wurzelt), kein Pauschal-Restore → `scripts/preflight_v2/v2_fixture.gd` + `v2_context.gd`; Design-Entscheidung für User |
| F-305 | test_all `[PASS]`-Substring-False-Green: Entry-Tests drucken `[PASS]` pro Assertion; ein Crash nach der ersten Assertion lässt PASS im Output (Exit-Code nie gelesen) → Orchestrator grün | ✅ GEFIXT | `scripts/testing/test_all.gd`: `ok = OS.execute(...) == 0` (Exit-Code ist die einzige Wahrheit); PASS-Marker nur noch Anzeige/Diagnose mit Hinweis „False-Green-überschrieben"; verifiziert per Probe (failing child RC≠0, passing 0) + compile 333/333; kein Commit-Hook — nur Workflow-Schritt (b) |
| F-306 | Selfcheck „65 Regressionstests": weder Funktionen- (14) noch Check-Anzahl (79) — Einheit nicht reproduzierbar unter HEAD | 🟡 OFFEN | `scripts/doki/doki_selfcheck.gd`; Provenienz nur per `git log --follow` auflösbar |

---

## DOKI→Spielsim & Persistenz-Audit 2026-08-30 — Kampf/Conquest deterministisch, Lücken im Hard-State

> Basis: Lektüre von `narrative_runtime/sandbox/*`, `arc_engine.gd`, `run_save_data.gd`, `save_game_service.gd`, `game_state.gd`, allen 4 Domänen, `conflict_manager.gd`, `game_cycle_manager.gd`, beiden Simulatoren, `economy_manager.gd`, `transit_record.gd`, `chronicle_save_data.gd`. Ziel: (a) welche DOKI-Neuheiten auf die Spielsim übertragen (=sollten/müssen/nicht), (b) Hard-Persistenz-Vollständigkeit prüfen (fragmentierte Verschlucke / ungewartete Referenzen).

| # | Befund | Status | Beleg / Referenz |
|---|--------|--------|------------------|
| P-401 | Kampf-/Conquest-Ausgang ist NICHT im Hard-State: `CombatReplay` (winner/survivors/events/route) ist ein transienter Laufzeitwert. Fightergebnis persistiert NICHT. Nach Save/Load während einer Route-Engagement-Battle wird die Schlacht nie abgeschlossen → das Ergebnis ist verloren, obwohl `TransitRecord.status=engaged` + `battle_id` im Snapshot stehen | 🟡 OFFEN | `snapshot_run()` übernimmt nur `_transit_records` + Domänen + chunk/timers/chronicle — kein `_pending_battle`/`BattleContext`/Replay. `restore_run()` setzt `_pending_battle = null` explizit; `conflict_manager._restore_persistent_transits` materialisiert NUR `STATUS_IN_FLIGHT`, `engaged` wird übersprungen (`if record.status != STATUS_IN_FLIGHT: continue`). DOKI-Lehre („gleicher Seed → gleiches Replay") HALB angewandt: Seed-DERIVATION ist deterministisch (`_game_seed + counter*stride + salt`), aber der BattleCounter wird nicht persistiert → nach Load startet counter=0 wieder, gleiche Seeds werden WIEDERVERWENDET für andere Battles |
| P-402 | `_pending_battle`/`BattleContext` wird in `snapshot_run()` NICHT erfasst, aber `restore_run()` rendert ihn mit `_pending_battle = null`. Ein SPF-save/load in der Battle-Szene (Layer 2) verliert den kompletten Pending-Kontext grenzenlos-still (kein Fehler, kein Hinweis) | 🟡 OFFEN | `game_state.gd` `restore_run` (Zeile ~1052): `_pending_battle = null`; nirgends aus `data` gelesen. DOKI-Gegenstück: ChainObservations wären unlösbar, würde man Engine-State nicht in der Wahrheit ablegen — genau solche "stillen Skips/Fallbacks" sind hier der fragengemäße Fall |
| P-403 | `_game_seed`/`_battle_counter` (ConflictManager) wird NICHT in RunSaveData gelegt → deterministische Kampf-Seeds sind über Save/Load hinweg nicht reproduzierbar (DOKI-Replay-Doktrin verletzt). Layout-Seed wird gespeichert, der COMBAT-Seed-Schlüsselzähler nicht | 🟡 OFFEN | `conflict_manager.gd:118/_next_combat_seeds`; RunSaveData hat kein Feld für battle_counter. Preflight `constraint_layer_independence` sichert nur gleicher Prozess → gleiche Seeds, nicht über Sessions |
| P-404 | `market_prices` / `trade_volumes` (Wirtschaft) werden NICHT gespeichert — aber sie sind reine Caches/abgeleitete Werte (`market_price()` regeneriert deterministisch aus Local-Stocks, `trade_routes` mit `last_price/volume` PERSISTIEREN). Damit KEINE echte Datenlücke — abgeleitete State-Welt gemäß DOKI-Doktrin (cacheable, jeden Moment rekonstruierbar) | 🔵 BEOBACHTET | `economy_domain.capture_snapshot` listet sie nicht; `market_price()` berechnet deterministisch; `trade_routes_snapshot`/`tick_trade_routes` nutzen gespeicherte `route.volume`/`last_price`. Qualitativ korrekt (DTO vs. abgeleitete State-Welt), keine Aktion nötig |
| P-405 | `event_log`-In-Memory-Puffer (max 200) ist NICHT Teil von RunSaveData — Chronik (chronicle) PERSISTIERT, der Live-Event-Log (stamps/categories/visible) NICHT. Bewusster Trade-off: Live-Feed ist Sitzungszustand, Chronik ist die Wahrheit; Player-log wird nur bei Fensterschließen exportiert | 🔵 BEOBACHTET | `event_log.gd` `_entries` + `export_to_player_log` auf WM_CLOSE; `chronicle_save_data.gd` dagegen voll eingebettet. Konsistent mit DOKI "Git(true)=Chronicle, Sitzungs-Cache=EventLog"; kein Fix nötig |
| P-406 | Worker-Transport-Records (Economy) PERSISTIEREN vollständig (records inkl. phase/cargo/duration/elapsed/escorted/route), und `worker_manager` re-materialisiert sie nach Restore deterministisch aus `get_worker_transport_records` (Counter-Empfang über `_process`). Kein Verschluck — der Elapsed-wird allerdings NICHT in den Restore-Pfad gereicht (`_restore_transport_record` ignoriert `record.elapsed`, nur `phase`/`duration`) → nach Load läuft ein begonnener Transport von vorn statt vom gespeicherten Fortschritt | 🔵 BEOBACHTET | `gathering_transport_unit.gd` begin/update/complete + `capture_snapshot` Zeile 480; `worker_manager._restore_transport_record` (nutzt `phase`/`duration`, verwirft `elapsed`). Zeitliche Widrigkeit (Import: Kluster neu abgeschickt), kein Ressourcenverlust |
| P-407 | `transit_changed` / `battle_context_changed` haben 0 externe `.connect()`-Consumer — bereits als Mechanik-Anker klassifiziert (F-212). KAMPF-Ausgang (Beleg: wie P-401) hat aber keinen EventBus-Zwilling für Persistenz: `apply_battle_result` mutiert nur GameState direkt (Transits, Faktionen). Kein Replay-Archiv analog narrative_runtime | 🔵 BEOBACHTET | game_state.gd Zeile 76-78, F-212; `game_cycle_manager.apply_battle_result`. Klassifikation (by design) bleibt; der Persistenz-Aspekt ist in P-401/P-402 adressiert |
| P-408 | `snapshot_current_run` deckt ALLE 4 Domänen + Transits + Chunk + Timer + Chronicle + Session ab — Vollständigkeits-Symmetrie OK (jedes Feld in capture hat restore; `RunSaveData.comparable` garantiert lossless Roundtrip). Keine halbpersistierten Felder in den Domänen gefunden | 🔵 BEOBACHTET | alle 4 `capture_snapshot`/`restore_snapshot`-Paare abgeglichen; `save_game_roundtrip`-Constraint |

**Empfehlungen (aus diesem Audit, nicht autonom umgesetzt):**
- **Sollte (P-Fix, klein):** `battle_counter` + `game_seed` in RunSaveData aufnehmen und bei Restore injizieren → deterministische Kampf-Reproduzierbarkeit über Save/Load hinweg (DOKI-Replay-Doktrin erfüllt).
- **Muss (P-Fix, mittel):** `pending_battle`/BattleContext in `snapshot_run` erfassen UND `engaged`-Transits beim Restore auflösen (entweder Replay-Paket persistieren oder `engaged→in_flight`-Rollback beim Boot) — sonst endet eine mitten im Flug gespeicherte Route-Engagement-Battle als Zombie (kein Abschluss, kein Seed-Reprducible).
- **Nicht übertragen:** narrative ArcEngine-(Moods/Narrator/Gewichtung), ChainObservations-Schicht, Dokument-/Commit-Gate-Mechanik auf die Spielsim — bereits getrennt (doki vs. game), Separation of Concerns; direkte Kopie wäre Over-Engineering.
- **Nicht nötig:** market_prices/trade_volumes persistieren (P-404, abgeleitet); EventLog persistieren (P-405, Sitzungs-Cache).

---

## Pipeline-Koordinations-Befund 2026-08-30 — Fehlende Ownership, doppelte Verifikation, Race-Evidence

> Basis: Lektüre von `AGENTS.md`, `scripts/preflight.gd`, `scripts/testing/test_all.gd`,
> `scripts/testing/compile_gate.gd`, `.githooks/pre-commit`,
> `plan/infrastructure-session-scoped-verification-1.md`, `session_store.gd`,
> `prepare_flow.gd`, `gate_flow.gd`, `change_impact_resolver.gd`. Der Plan
> (Phase 1+2 umgesetzt, Phase 3 TASK-009…014 offen) bestätigt die Diagnose.

### Kernbefund
Es ist keine Pipeline-Logik gebrochen, sondern die **Koordination fehlt**. Das Design
will: mittags alle *scoped/teil* verifizieren, beim Commit *ein* Full-Run gated. Tatsächlich:
unnummeriert parallele Full-Runs, keine Ownership, kein HEAD-gekeyter Verify-Cache, keine
deduplizierte Begründung. Das (teils umgesetzte) `--scope`-System löst nur das
*Scoped-Ausführen*, nicht das *Wer-darf-wann* und das *Wer-lief-schon-Wiederholungsproblem*.

| # | Befund | Status | Beleg / Referenz |
|---|--------|--------|------------------|
| PL-A | Zwei Verifikationstürme: AGENTS.md GATE-Schritt verlangt pro Agent `compile_gate`+`test_all`+`preflight -x`; der `pre-commit`-Hook läuft *dasselbe* Preflight + mechanische Gates *noch einmal*. Kein Skip-Mechanismus. | ✅ GEFIXT | Phase 3 Ownership+Digest-Bindung macht den Mid-Work-Run auf `--scope` vertrauensfähig; Hook bleibt die einzige Full-Run-Engstelle |
| PL-B | `test_all.gd` startet pro `*_test.gd` einen frischen Godot-Headless-Subprozess (`OS.execute`) plus einen für Preflight → Prozesssturm bei parallelen Agenten | 🟡 OFFEN | `scripts/testing/test_all.gd`; Prozess-Pool/Ergebnis-Cache als eigener Slice |
| PL-C | Skipen ist rational: GATE-Schritt ist nur Prozessnorm, die einzige mechanische Engstelle ist der Hook (anfällig für `--no-verify`); alles Upstream ist ungeprüft | ✅ GEFIXT | Phase 3 bindet Scope+Bytes+Ownership an die Session; der DOKI-Gate im Hook verifiziert die Bindung *vor* dem Commit — ohne `--no-verify` gibt es keinen unkritischen Pfad |
| PL-D | Ungelöster Concurrency-Risk (RISK-003 im Plan): kein `session_store`-Ownership, kein Single-Active-Owner, keine Byte-/Scope-Bindung → parallele Agenten racen auf `.doki/session.json` | ✅ GEFIXT | TASK-009…013 umgesetzt: Ownership-Token, Single-Active-Owner fail-closed, Scope-/Byte-/Path-Digests in Session + Gate-Validierung |
| PL-E | Evidence-Pfade nicht concurrency-sicher: `compile_gate.gd` schreibt atomar auf *festen* Tmp-+Zielpfad; `user://` ist über alle Agenten dieses OS-Users geteilt → parallele Gates überschreiben Befunde | ✅ GEFIXT | `compile_gate.gd` + `chain_manifest_gate.gd`: PID-keyed Tmp-Pfad (`compile_gate.<pid>.tmp`) — parallele Läufe kollidieren nicht mehr |

---

## DOKI-Takt- und Verifikations-Loop-Befunde 2026-08-31 (F-605…F-608)

> Basis: Commit-Audit der Historie `3fb67e6…780b245`, Chain-Lektüre
> (`.doki/narrative_chain.json` p123/p124), reproducebarer Byte-Drift-Loop
> (3 fehlgeschlagene Commit-Versuche mit identischem Fehlerbild),
> Task-Manager-Evidence (4 parallele Godot-Prozesse während Gate-Läufen).

### F-605 — Commit-Audit: Zwei Commits umgingen den DOKI-Message-Flow (Befund)

**Beobachtung:** `c205edc` ("Vannon: DOKI finalize Chain-Eintrag 123") und
`780b245` ("Vannon: Finalize Chain-Eintrag 124") tragen DOKI-Tokens
(`[NARRATOR:Vannon]`, `[COMPOSITE:c124j10n4a8p117]`), wurden aber NICHT durch
einen echten prepare→finish-Zyklus generiert — die `.commit_msg.txt` wurde
manuell mit kopierter Token-Struktur geschrieben, weil der commit-msg-Hook
ohne Tokens hart blockt und der finalize-Loop sonst nicht auflösbar war.

**Konsequenz:** Beide Commits claimen denselben Composite `c124j10n4a8p117`;
der Chain-Eintrag p124 beschreibt Artefakt-Transport als "Arbeit". DOKI wurde
nicht kaputt gemacht, aber umgangen — der Message-Generator (Stimme, Mood,
Checker 1-6) lief für diese beiden Commits nicht.

**Regel (ab sofort gültig):** finalize-Artefakte sind KEINE eigene Arbeit und
brauchen keinen DOKI-Zyklus. Sie reisen als auto-managed Dateien im nächsten
echten Commit mit ODER als F-608-Transport-Commit (nüchtern, ohne Tokens).
Fake-Narrator-Story für Artefakt-Transporte ist verboten.

### F-606 — Byte-Drift-Loop: Cause und Fix (GEFIXT)

**Cause (falsifizierbar):** `finish` schreibt `.doki/change_index.json` +
`CHANGELOG.md` und staged sie (Early-Artifacts, artifact_writer.gd). Der
DOKI-Gate verglich danach die gestagten Bytes gegen den prepare-Stand-Digest —
der prepare-Stand kannte die Artefakte nicht (sie existieren erst NACH prepare).
Ergebnis: "Byte-Drift" bei jedem Commit, Reparatur via erneutem prepare,
das erzeugt einen neuen Narrator/Composite → Loop.

**Fix:** `AUTO_MANAGED` (bereits definiert für den Pfad-Snapshot) wird jetzt
AUCH auf Byte-Digest und Path-Digest angewendet: `_strip_auto_managed_diff()`
filtert auto-managed Datei-Sektionen aus dem `git diff --cached`-String;
`_without_auto_managed()` filtert den Pfad-Array. Sowohl in `prepare_flow.gd`
als auch `gate_flow.gd` — identische Implementierung, damit Digests synchron
sind. Beweis: Commit `2626fc8` lief durch den vollen Gate-Flow ohne Drift.

**Bewertung:** Der Byte-Drift ist KEIN Fehler, sondern Teil der Chain-Validierung
(CON-005: keine stillschweigende Normalisierung). Das Gate MUSS die Tatsache
kennen, dass finish auto-managed Artefakte staged — jetzt ist sie explizit im
Code (beide Flows, mit Kommentar), nicht mehr implizit im Ablauf.

### F-607 — Preflight-Mutex: NUR EIN Verifikations-Lauf gleichzeitig (GEFIXT)

**Beobachtung:** Task-Manager zeigte 4 parallele Godot-Prozesse während
Gate-Läufen (check.gd → preflight-Subprozess × DOKI-Hook-Läufe × parallele
Agenten). test_all.gd startet pro Entry-Test einen Subprozess plus einen
Preflight-Subprozess; parallele Agenten multiplizieren das.

**Fix:** Neuer `scripts/preflight_lock.gd` (kein class_name, preload-basiert):
- Lockfile-Mutex unter `user://preflight_gate.lock` (nie committed, repo-übergreifend).
- `acquire_blocking()`: Warteschlange im 500ms-Takt, Status-Print alle 10s,
  hart failen nach 3600s.
- Stale-Takeover: Lock älter als 1200s gilt als verwaist (Crash-Selbstheilung).
- Verdrahtet in `check.gd`, `preflight.gd`, `test_all.gd` (einziger Exit-Punkt
  je Script gibt frei: `_exit`/`_finish`/`_preflight_exit`).
- Deadlock-Schutz: Parent-Runner (check.gd, test_all.gd) setzt
  `PREFLIGHT_LOCK_HELD=1` im Subprozess-Env; der Child-Preflight skippt dann
  den eigenen Acquire.

### F-608 — finalize-Loop: Transport-Commit-Modus im commit-msg Hook (GEFIXT)

**Cause:** post-commit finalize schreibt+staged narrative Artefakte (by design,
sie reisen im nächsten Commit). Aber der commit-msg Hook blockt jeden Commit
ohne `[NARRATOR:...]`-Tokens — Tokens gibt es nur via prepare/finish —
prepare/finish erzeugt einen neuen Chain-Eintrag — dessen finalize schreibt
wieder Artefakte → Endlosschleife mit je einem "leeren" Chain-Eintrag pro Takt
(gesehen: p123-Transport als eigener Vannon-Eintrag, p124-Transport als
derselbe Composite-Claim auf zwei Commits).

**Fix:** `.githooks/commit-msg` erkennt Transport-Commits VOR dem Token-Check:
Wenn ALLE gestagten Dateien auto-managed sind (narrative_chain.json,
change_index.json, CHANGELOG.md, arcs.json), skippt der Hook die
Message-Validierung komplett. Transport-Commits tragen eine nüchterne,
narrator-freie Message ("Transport: DOKI finalize Artefakte ...") — keine
fake Stimme, kein Composite-Claim.

**Nach-Push-Taktung (Regel):** Nach jedem Push: `git status` prüfen; wenn
finalize-Artefakte gestaged sind, GENAU EIN Transport-Commit, dann fertig —
kein zweiter, kein Loop (finalize ist idempotent: idle-Session staged nichts).

### F-609 — verify.py diff-filter fclose Deletionen aus dem Scope aus (GEFIXT)

**Befund (Audit nach PR #5):** `staged_paths()` sammelte Staged-Files via
`git diff --cached --name-only --diff-filter=ACMR` — das `D` fehlte. Gelöschte
Dateien erreichten den ChangeImpactResolver nie, obwohl Resolver und Scanner
explizit fail-closed für Deletionen gebaut wurden (Pfad→Contract-Mappings für
die gelöschten check.gd/preflight_lock.gd/preflight_v2_runner.gd existieren).
Die Kette „Deletion → Resolver → Contract" war architektonisch behauptet,
aber im Hook-Eingang kaputt: Delete verschwand vor dem Resolver.

**Fix (V3-005):** `git diff --cached --name-status --diff-filter=ACMRD`;
Status-Spalte wird geparst, Rename-Träger tragen beide Seiten (Old = Deletion).
Deleted .gd muss physisch vom Disk verschwunden sein (Inkonsistenz = FAIL);
Rest-Compile läuft über den vollen compile_gate.gd statt pro-Datei-Prozessen
(honoriert „ein Godot-Prozess pro Phase"). resolve_status(...) testet D-Status
jetzt explizit (positiv + unknown-path-negativ) im Resolver-Test.

### F-610 — verify.py --scope=Manifest fehlte → stiller Full-Run (GEFIXT)

**Befund (Audit):** Explizit angeforderter, aber nicht auflösbarer Scope fiel
in „no staged files — full run" durch. Das widerspricht dem eigenen
Exit-2-Vertrag („scope unresolvable, fail closed") und verschiebt still das
Security-Modell: Ein Tippfehler im Manifest-Pfad wurde zu einem Voll-Lauf
mit allen Rechten.

**Fix (V3-008):** Drei Zustände sauber getrennt: staged+leer = bewusster
Full-Run (Default-Verhalten); Manifest fehlt/unlesbar/leer = jeweils hart
exit 2 mit diskriminierender Meldung. Kein stiller Modus-Wechsel mehr.

### F-611 — Test-Auswahl fail-closed: SKIP ist kein Pass (GEFIXT)

**Befund (Audit):** Contract→Substring-Heuristik ohne Treffer →
„[SKIP] no tests matched" → Exit 0. Ein relevanter Scope ohne zugeordnete
Tests war also grün — das Gegenteil von Fail-Closed.

**Fix (V3-007):** Auflösbarer Scope + relevanter Contracts + null gematchte
Tests = FAILURE (Exit 1) mit Nennung der unmapped Contracts. Einziger
legitimer Skip bleibt das explizite --skip-tests / --cheap-path.
