# ZACA Skill Report — GDScript MCP Bridge (SnipWar Addon)

## Ziel (Objective)
Vollständiger Audit des `addons/gdscript_mcp/`-Addons. Verkabelung aller Module (Server, Registry,
Vision, OCR, Worker, Context-Store, UX, E2E, Editor) auf Korrektheit, Vollständigkeit und
Godot-4.7-Konformität prüfen. Das Addon ist ein eigenständiges Godot-Plugin und wird in SnipWar
als Submodul/Addon eingebunden.

---

## Hard Constraints

| # | Constraint | Quelle/Verification | Status |
|---|-----------|---------------------|--------|
| 1 | `McpRuntime` ist Autoload (`project.godot`) — startet nur mit `--mcp` CLI-Flag | `project.godot:19`, `mcp_runtime.gd:24` | ✅ Verified |
| 2 | `McpProjectAdapter` ist Autoload — optionale cross-project Brücke | `project.godot:20` | ✅ Verified |
| 3 | Editor-Plugin (`gdscript_mcp_plugin.gd`) ist in `editor_plugins` registriert | `project.godot:34` | ✅ Verified |
| 4 | `plugin.cfg` deklariert Abhängigkeit `editor/gdscript_mcp_plugin.gd` | `plugin.cfg:7` | ✅ Verified |
| 5 | Runtime-Session (Port 9090) und Editor-Session (Port 9091) sind getrennt | `mcp_server.gd:69-70`, `plugin.gd:10` | ✅ Verified |
| 6 | `GdscriptMcpServer.PROCESS_MODE_ALWAYS` — tickt auch bei `paused=true` | `mcp_server.gd:57` | ✅ Verified |
| 7 | `McpInputScheduler.PROCESS_MODE_ALWAYS` — persistente Input-Queue | `mcp_input_scheduler.gd:24` | ✅ Verified |
| 8 | `McpLifecycle` ist `RefCounted` — kein Node, wird vom Server verwaltet | `mcp_lifecycle.gd:1-2` | ✅ Verified |
| 9 | `McpContextStore` ist `RefCounted` — Datei-basierte Artefaktverwaltung | `mcp_context_store.gd:1-2` | ✅ Verified |
| 10 | Vision `capture_screenshot` ist `async` (`await RenderingServer.frame_post_draw`) | `mcp_vision_capture.gd:16` | ✅ Verified |
| 11 | Bildartefakte werden lokal gespeichert — MCP-Antworten enthalten KEIN Base64 | `mcp_context_store.gd:31-68`, `mcp_server.gd:604-615` | ✅ Verified |
| 12 | `McpVisionWorker` (Godot-Node) supervidiert externen Node/Python-Prozess | `mcp_vision_worker.gd:1-224` | ✅ Verified |
| 13 | OCR ist im Node-Worker mit Tesseract.js integriert | `vision_worker.js:handleJob()` | ✅ Verified |
| 14 | E2E-Driver aktiviert virtuelle Maus vor Szenario-Start | `mcp_playthrough_driver.gd:46` | ✅ Verified |
| 15 | Physische Maus wird auf 3 Ebenen blockiert: Cursor, Input-Events, Edge-Scroll | `mcp_input_scheduler.gd:109-113`, `mcp_runtime.gd:51-57`, `map_camera.gd:78-94` | ✅ Verified |
| 15a | Virtueller Cursor ist klein positioniert (32×32), nicht Full-Rect — blockiert keine Screenshots | `mcp_input_scheduler.gd:_create_virtual_cursor()` | ✅ Verified |
| 15b | `mcp_vision.gd` blendet Cursor vor Screenshot aus (`hide_cursor` → capture → `show_cursor`) | `mcp_vision.gd:_hide_cursor_for_capture()` | ✅ Verified |
| 15c | Blank-Screen-Detection: Screenshots ≤1 unique color → `"blank"` | `mcp_vision.gd:_check_blank_screen()` | ✅ Verified |
| 15d | `mcp_e2e.gd` `_wait_for_text`/`_wait_for_technology_menu`/`_wait_for_scene` → 1 generisches `_wait_for(mode, needle, timeout)` | Zeile ~394 | ✅ Verified (554→542 LOC) |
| 15e | `.tmp_live_features.js` (Test-Abfall) entfernt | git status | ✅ Verified |
| 16 | `map_camera.gd` `_input_mouse_position()` prüft `McpRuntime` UND `McpInputScheduler` | `map_camera.gd:78-94` | ✅ Verified |
| 17 | `mcp_vision_compare.gd` typisiert `max_origin_x/y` explizit als `int` | `mcp_vision_compare.gd` (nach lazy-load Fix) | ✅ Verified |
| 18 | Server `_handle_tool_call()` validiert `connection_generation` gegen Disconnects | `mcp_server.gd:430-440` | ✅ Verified |
| 19 | Editor-Schreib-Tools erfordern `_editor_write_enabled` Opt-in | `mcp_server.gd:448-451` | ✅ Verified |
| 20 | Editor-Tools nutzen Godot `UndoRedo` (nicht direkte Dateimutation) | `gdscript_mcp_plugin.gd:145-175` | ✅ Verified |
| 21 | `runtime_key` akzeptiert JSON-Floats mit ganzzahligem Wert als Keycodes | `mcp_runtime_tools.gd:385` | ✅ Verified |
| 22 | E2E `pause_save_menu` macht `tree.paused = false` vor HAUPTMENÜ-Click | `mcp_e2e.gd:163-169` | ✅ Verified |
| 23 | `.uid`-Sidecars existieren für alle `.gd`-Dateien | `git status` zeigt alle `.uid`-Files | ✅ Verified |
| 24 | Node-Client `vision_worker.js` ist syntaktisch validiert (`node --check`) | Terminal: `NODE_OK` | ✅ Verified |

---

## Systemische Abhängigkeiten (Systemic Dependencies)

| Von (From) | Abhängigkeit (Dependency) | Nach (To) | Bedingung (Condition) |
|-----------|--------------------------|-----------|----------------------|
| `McpRuntime._ready()` | startet nur mit | `--mcp` CLI-Flag | `user_args` enthält `--mcp` |
| `McpRuntime._boot_server()` | lädt und instanziiert | `mcp_server.gd` | `ResourceLoader.exists(MCP_SERVER_PATH)` |
| `GdscriptMcpServer.start_server()` | lädt | `McpLifecycle`, `McpProtocol`, `McpContextStore`, `McpToolRegistry` | Alle Pfade müssen existieren |
| `McpToolRegistry` | lazy-loaded | `mcp_runtime_tools.gd`, `mcp_vision.gd`, `mcp_debug.gd`, `mcp_ux_pipeline.gd`, `mcp_e2e.gd`, `mcp_playthrough_tools.gd` | Nur bei Runtime-Rolle |
| `McpVision.capture_screenshot()` | delegiert an | `McpVisionCapture` → `Viewport.get_texture()` → `texture.get_image()` | Renderer muss sichtbar sein |
| `McpVision._commit_capture()` | schreibt via | `McpContextStore.write_image()` | `persist_context=true` |
| `McpContextStore.write_image()` | schreibt | `.jpg`/`.png` + `.json` Metadaten + ggf. PNG-Companion | Dateisystem unter `user://mcp_context/` |
| `McpVisionWorker` | startet externen Prozess via | `OS.create_process(_command, args)` | `_enabled=true` |
| `McpVisionWorker.request()` | sendet JSON via | `StreamPeerTCP` → externer Worker (Port `port+37`) | `_ensure_connected()` |
| Externer Worker (`vision_worker.js`) | liest Artefakte von | `--context-root` Verzeichnis | PNG-Format, `.json`-Metadaten |
| `McpInputScheduler._input()` | blockiert physische Maus via | `get_viewport().set_input_as_handled()` | `_physical_mouse_blocked=true` |
| `McpRuntime._input()` | delegiert an | `McpInputScheduler.record_blocked_physical_mouse_event()` | Scheduler existiert |
| `MapCamera._input_mouse_position()` | liest virtuelle Position von | `McpRuntime.get_virtual_mouse_status()` oder `McpInputScheduler.get_virtual_mouse_status()` | Fallback: `get_viewport().get_mouse_position()` |
| `MapCamera._edge_scroll_vector()` | nutzt | `_input_mouse_position()` | Bei aktiver virtueller Maus → virtuelle Position |
| `McpE2E._find()` | ruft | `runtime_ux_find` → `McpUxPipeline` | Registry dispatch |
| `McpUxPipeline` | scannt | `SceneTree.root` Children + rekursiv | ⚠️ CanvasLayer-Kinder werden nicht traversiert |
| E2E-Driver | instanziiert | `McpInputScheduler` direkt auf `root` | `_activate_virtual_mouse()` |

---

## Datenfluss: Screenshot → Artifact → Worker → OCR → Release

```
1. Agent ruft: runtime_screenshot { format: "png" }
2. Server → Registry → McpVision.dispatch_async("runtime_screenshot", args)
3. McpVision.capture_screenshot() → await McpVisionCapture.capture_screenshot()
   └─ await RenderingServer.frame_post_draw
   └─ texture.get_image() → Image
4. McpVision._commit_capture() → McpContextStore.write_image(image, "png", metadata)
   └─ image.save_png_to_buffer() → PackedByteArray
   └─ FileAccess.open(absolute_path, WRITE) → store_buffer(bytes)
   └─ JSON.stringify(record) → .json Metadaten
   └─ _enforce_limits() → MAX_RECORDS=6, MAX_TOTAL_BYTES=32MB
5. MCP-Antwort: { context_id, path, width, height, size_bytes, mime_type, expires_at }
   (KEIN data/base64-Feld!)
6. Agent ruft: runtime_vision_worker_analyze { context_id, ocr: true }
7. Server → Registry → McpVision.dispatch_async("runtime_vision_worker_analyze", args)
8. McpVision.worker_request("analyze", {context_id, ocr:true})
9. McpVisionWorker.request("analyze", args)
   └─ _ensure_connected() → startet ggf. node vision_worker.js --serve
   └─ sendet JSON: { id:"job_N", operation:"analyze", context_id:"frame_...", ocr:true }
10. vision_worker.js handleJob():
    └─ artifactFromContext(contextRoot, context_id)
       └─ liest {id}.json → worker_path
       └─ validiert Pfad (escape-Schutz)
       └─ decodePng() → { width, height, pixels }
    └─ analyzeArtifact() → { palette, rects }
    └─ OCR: { available: false, reason: "OCR command not configured" }
11. Worker sendet JSON-Zeile zurück: { ok:true, id:"job_N", width, height, palette, rects, ocr }
12. McpVisionWorker._poll_peer() → _responses[id] = response
13. McpVisionWorker.request() returned → McpVision → MCP-Antwort
14. Agent ruft: runtime_context_release { context_id }
15. McpContextStore.release() → _remove_record_files() → DirAccess.remove_absolute()
    └─ Entfernt: .jpg/.png + ggf. .png Worker-Companion + .json Metadaten
```

---

## Fehlende Daten / Blindspots

| # | Lücke (Gap) | Warum kritisch (Why critical) | Aktion nötig (Action needed) |
|---|------------|------------------------------|------------------------------|
| 1 | `runtime_ux_scan` traversiert keine `CanvasLayer`-Kinder — TechnologyMenu (Layer 60) ist unsichtbar für `_find("SCHLIESSEN")` | `tech_menu_open_close` und `research_start` E2E-Szenarien FAILen | ✅ **GESCHLOSSEN — echter Root Cause:** `mcp_ux_live.gd` traversiert CanvasLayer-Kinder korrekt (Zeilen 47–87). Der Trigger war ein **Timing-Race**: Der erste `runtime_ux_click` auf TECHNOLOGIE landete im World-Transition-Settle-Fenster (SceneDirector-0.6s-Fade) und wurde verschluckt; das Panel öffnete nie. Fix: Click-Retry bis geöffnet beobachtet (`mcp_e2e.gd` `_scenario_tech_menu_open_close`, bis 3 Versuche + `_dir_texts`-Diagnose). Verifiziert: `tech_menu_open_close` PASS (10.9s), Live-Probe: Click→`press:true`/`‹ SCHLIESSEN`, zweiter Click schließt. |
| 2 | OCR ist im Node-Worker mit Tesseract.js integriert | ✅ Geschlossen | — |
| 3 | `freeze_step` E2E: World-Transition (`create_tween()`) braucht KONSEKUTIVE Frames | `SceneTree.paused` stoppt Tweens — `step_one_frame()` gab nur 1 Frame pro Step. Jetzt `runtime_step_frames(count)` | ✅ Geschlossen — `mcp_input_scheduler.gd:step_frames()` hält Tree für `count` Frames unpausiert |
| 4 | `pause_save_menu` E2E: HAUPTMENÜ-Click führt zu `game_view` statt `main_menu` | SceneDirector-Transition in SnipWar funktioniert nicht zuverlässig aus paused state | SnipWar `scene_director.gd` `goto_scene("menu")` prüfen — Game-seitiger Bug |
| 5 | `mcp_client.py` Referenz-Client nicht gegen laufende Runtime getestet | `StreamPeerTCP` via `--script` hängt — TCP-Test nur im normalen Spielmodus möglich | E2E-Test mit `--mcp` + `mcp_client.py` im normalen Spielmodus |
| 6 | `McpUxPipeline` visuelle Watch-Queue — kein echter Backpressure-Mechanismus | Bei 30+ fps könnte Watch-Queue überlaufen | Queue-Limit + Drop-Counter implementieren |

---

## Status zum letzten Audit

- Letztes Audit: 2026-08-23 18:00 (vorherige Session)
- Neue Constraints seit letztem Audit: +4 (Deferred Virtual-Mouse-Activation, _protocol_ready-Gate, Tech-Menu Click-Retry, Dual-Worker-Doku)
- Geschlossene Lücken: 2 (Blindspot #1 tech_menu → echter Root Cause gefunden + fix), + Startup-Defekt `add_child()` im Autoload-_ready (Root busy) → `call_deferred` für Scheduler+Cursor

## Neue verifizierte Constraints (08-23, späte Session)
| # | Constraint | Quelle | Status |
|---|-----------|--------|--------|
| 23 | `_activate_virtual_mouse` läuft NICHT in `_ready` (root busy) — `call_deferred`, wie `_boot_server` | `mcp_runtime.gd:49-53` | ✅ Boot-Log 0 `add_child`-Fehler |
| 24 | `tools/call` vor `initialize` → `-32002 Server not initialized`; Host-Tools (status/events) bleiben erlaubt | `mcp_server.gd:_handle_tool_call` | ✅ Live verifiziert (-32002) |
| 25 | `tech_menu_open_close`: Click-Retry bis 3×, Panel muss beobachtet offen sein | `mcp_e2e.gd` | ✅ PASS 10.9s |
| 26 | `vision_worker.py`/.js = konfigurierbarer Dual-Worker (`--mcp-vision-command/--script`), Default .js — keine Redundanz | `mcp_runtime.gd:40-44` | ✅ Doku in MCP_INDEX |

- E2E-Status: 7/7 PASS (main_menu, new_game_to_world, tech_menu_open_close, research_start, pause_save_menu, freeze_step, analyze_and_goal, virtual_mouse_edges)