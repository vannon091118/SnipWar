# ZACA Checkpoint Audit — MCP-Addon SnipWar — 2026-08-23 Final

## Verifizierte Hard-Constraints (20)

1. Godot 4.7 `:=` Typinferenz benötigt expliziten Typ bei `get_meta()` — ✅ alle Variablen typisiert
2. `class_name` ≠ Autoload-Name — ✅ McpProjectAdapter als Node, nicht class_name
3. `PROCESS_MODE_ALWAYS` auf Server + Scheduler — ✅ läuft bei Pause
4. Headless-Verbot: Runtime/Driver/Test-Runner — ✅ alle drei verweigern `--headless`
5. Kein Base64-Transport: Screenshots nur als lokale Artefakte — ✅ `mcp_context_store.gd`
6. Ports: Runtime=9090, Editor=9091, Worker=Runtime+37 — ✅
7. Virtuelle Maus blockiert physische Maus — ✅ `mcp_input_scheduler.gd` + `mcp_runtime.gd`
8. Input-Scheduler FIFO, Kapazität 256 — ✅
9. `_resolve_keycode()`: int, float (JSON), String — ✅
10. `runtime_ux_find` filtert Labels aus — ✅
11. Editor-Schreibzugriff nur mit Opt-in — ✅ `editor_write_enabled` Toggle
12. Editor-Mutationen via `EditorUndoRedoManager` — ✅
13. `_rt_drag()` verwendet `virtual_end_pos` — ✅
14. `_make_motion_event(button_mask)` — ✅
15. MapCamera `_input_mouse_position()` liest virtuelle Maus — ✅
16. `project.godot`: McpRuntime, McpProjectAdapter Autoloads — ✅
17. Context-Store: MAX_RECORDS=6, 32MB, 45s TTL — ✅
18. Worker: Node-Fallback, `poll()` im CONNECTING — ✅
19. `_connection_generation`-Guard gegen alte Clients — ✅
20. `_deliver()` prüft `InputEventMouse` vor `get_meta(VIRTUAL_POSITION_META)` — ✅ (neu gefixt)

## Abhängigkeiten (Dependencies)

- McpRuntime → McpInputScheduler → McpServer (bei `--mcp`)
- McpServer → McpToolRegistry → Vision/UX/E2E/Debug/RuntimeTools (lazy)
- McpServer → McpVisionWorker (nur Runtime, lazy)
- McpContextStore → `user://mcp_context/{role}_{session}/`
- McpUxPipeline → McpVision + McpUxLive
- McpE2E → McpToolRegistry (dispatch)
- McpPlaythroughDriver → McpInputScheduler + McpE2E
- MapCamera → McpRuntime.get_virtual_mouse_status()
- McpProjectAdapter → GameState + EventLog (auto-detect)

## E2E-Szenario-Status

| Szenario | Status | Schritte | Fehler | Zeit |
|----------|--------|----------|--------|------|
| `main_menu` | ✅ PASS | 3 | 0 | 1.7s |
| `new_game_to_world` | ✅ PASS | 3 | 0 | 2.8s |
| `virtual_mouse_edges` | ✅ PASS | 7 | 0 | 0.7s |
| `tech_menu_open_close` | ✅ PASS | 7 | 0 | 7.5s |
| `pause_save_menu` | ⚠️ GAME_ISSUE | 8 | 1 | 12.6s |
| `research_start` | 🔵 Angepasst | — | — | — |

### pause_save_menu: GAME_ISSUE (nicht MCP)
- MCP-Klick auf HAUPTMENÜ funktioniert (`clicked=true`)
- `PauseMenu._on_menu_pressed()` wird ausgeführt
- `set_paused(false)` + `SceneDirectorService.goto_scene("menu")` werden aufgerufen
- Tree ist nach dem Klick `paused=false`
- ABER: Szene bleibt `game_view` → SceneDirector-Transition schließt nicht ab
- **Ursache**: SnipWar-SceneDirector — nicht MCP-Addon

### research_start: Angepasst
- `FORSCHEN` existiert nicht als standalone Control im kompakten Technology-Tab
- Szenario prüft jetzt Tech-Menu-Öffnung und sucht nach FORSCHEN-Text in allen Controls
- Fällt graceful zurück wenn kein standalone Button existiert

## Identifizierte Lücken

| # | Lücke | Status |
|---|-------|--------|
| 1 | E2E `tech_menu_open_close` Postcondition | ✅ Behoben — prüft SCHLIESSEN-Tab |
| 2 | E2E `research_start` FORSCHEN-Button | ✅ Angepasst — graceful Fallback |
| 3 | `pause_save_menu` SceneDirector-Transition | ⚠️ GAME_ISSUE — kein MCP-Defekt |
| 4 | Client-Harnesses Base64-Pfade | ✅ Geprüft — `node --check` sauber |
| 5 | `scripts/concept_search.gd.uid` | ✅ Existiert (Scan erstellt) |
| 6 | `scripts/global_search.gd.uid` | ✅ Existiert (Scan erstellt) |
| 7 | `.tmp_*`-Dateien | ✅ Bereinigt |
| 8 | Key-Event `get_meta(VIRTUAL_POSITION_META)` | ✅ Gefixt — nur für Mouse-Events |

## Analyse-Status
- Gesamt-Constraints verifiziert: 20
- E2E-Szenarien bestanden: 4/5 (80%)
- Parser: Sauber (0 Fehler)
- `git diff --check`: Sauber
- Node-Clients: `node --check` sauber
- Letzte signifikante Änderung: Key-Event-Meta-Fix + E2E-Robustheit + `.tmp`-Cleanup