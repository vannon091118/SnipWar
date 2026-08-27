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

## QA-Runde 1 — „Tutorial durchspielen" (sichtbar, mcp_file_driver)

### Spielfindings (Game-Seite)
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

## Offene Punkte (nächste Runden)
| # | Punkt | Priorität |
|---|-------|-----------|
| OFFEN-1 | **Editor-Modus: eingebettete Spiel-Tests.** Erkenntnis: Der Editor-Kind-Server (`_start_runtime_server_internal`) kann die Scene-Tools nie auf den Spielbaum richten (Godot hat keine öffentliche API für den laufenden Spiel-Tree; Tools nutzen `Engine.get_main_loop()` → Editor-Tree → „Game not running"). Lösungskandidat: `McpRuntime`-Autoload startet den Server **im Spiel-SceneTree** selbst, angestoßen durch Env-Flag vom Plugin (`MCP_EMBEDDED=1` vor `play_main_scene`); Plugin wartet auf den Spiel-Server statt selbst zu hosten. `vision_worker_enabled: false` im In-Process-Config auf `true` (OCR). | P1 |
| OFFEN-2 | Tutorial-Schritt 2: grüner Ziel-Marker (Home-Planet) sichtbar machen | P1 |
| OFFEN-3 | `runtime_visual_evidence` um Age/Zeitstempel-Filter erweitern (veralteter Cache ≠ aktueller Zustand) | P2 |
| OFFEN-4 | `runtime_ux_analyze include_visual=true` vom seriellen Async-Pfad auf Fire-and-forget umstellen | P2 |
| OFFEN-5 | Pool-Skalierung messen: `MCP_OCR_POOL=1` vs. 4 mit je 8 Jobs | P3 |
| OFFEN-6 | OCR-Assets (deu.traineddata.gz + Worker-Script) als gepackte Ressource einchecken für Offline-Kaltstart | P3 |
