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

## Offene Punkte (nächste Runden)
| # | Punkt | Priorität |
|---|-------|-----------|
| OFFEN-1 | **Editor-Modus: eingebettete Spiel-Tests.** Erkenntnis: Der Editor-Kind-Server (`_start_runtime_server_internal`) kann die Scene-Tools nie auf den Spielbaum richten (Godot hat keine öffentliche API für den laufenden Spiel-Tree; Tools nutzen `Engine.get_main_loop()` → Editor-Tree → „Game not running"). Lösungskandidat: `McpRuntime`-Autoload startet den Server **im Spiel-SceneTree** selbst, angestoßen durch Env-Flag vom Plugin (`MCP_EMBEDDED=1` vor `play_main_scene`); Plugin wartet auf den Spiel-Server statt selbst zu hosten. `vision_worker_enabled: false` im In-Process-Config auf `true` (OCR). | P1 |
| OFFEN-2 | Tutorial-Schritt 2: grüner Ziel-Marker (Home-Planet) sichtbar machen | P1 |
| OFFEN-3 | `runtime_visual_evidence` um Age/Zeitstempel-Filter erweitern (veralteter Cache ≠ aktueller Zustand) | P2 |
| OFFEN-4 | `runtime_ux_analyze include_visual=true` vom seriellen Async-Pfad auf Fire-and-forget umstellen | P2 |
| OFFEN-5 | Pool-Skalierung messen: `MCP_OCR_POOL=1` vs. 4 mit je 8 Jobs | P3 |
| OFFEN-6 | OCR-Assets (deu.traineddata.gz + Worker-Script) als gepackte Ressource einchecken für Offline-Kaltstart | P3 |
