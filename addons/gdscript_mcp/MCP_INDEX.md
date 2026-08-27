# GDScript MCP Bridge — Index & Dokumentation

**MCP-Protokoll** (Model Context Protocol, JSON-RPC 2.0) über stdio/TCP.
Macht jedes Godot-4.x-Projekt für externe Tools (KI-Agents, Test-Frameworks)
fernsteuerbar — **Scope: Editor-Inspektion sowie Remote-Testing eines sichtbaren
laufenden Spiels** (Live-Playthrough, UI/UX-Vision, Playability-Tests). Das Add-on
enthält keine Spiel- oder SnipWar-Logik; projektspezifische State-/Log-Brücken sind
optional und werden über `application/mcp/*` konfiguriert oder automatisch entdeckt.

---

## Architekturübersicht

```
┌──────────────────────────────────────────────────────────────────┐
│  MCP Client (extern)  —  Runtime TCP 127.0.0.1:9090 / Editor 9091 │
└────────────────────────────┬─────────────────────────────────────┘
                             │ JSON-RPC 2.0 (newline-delimited)
┌────────────────────────────▼─────────────────────────────────────┐
│  GdscriptMcpServer  (runtime/host/mcp_server.gd)                 │
│  • OWN LIFECYCLE: PROCESS_MODE_ALWAYS (tickt auch im Pause-Menü) │
│  • eigener Transport-Poll (_process), Async-Queue für await-Tools│
│  • Lifecycle + Latenz-Tracking (runtime/mcp_lifecycle.gd)        │
│  • Protokoll-Modul (runtime/protocol/mcp_protocol.gd)            │
└────────────────────────────┬─────────────────────────────────────┘
                             │ delegate
┌────────────────────────────▼─────────────────────────────────────┐
│  McpToolRegistry  (runtime/core/mcp_tool_registry.gd)            │
│  Lazy-Load, Prefix-Routing, Sync/Async-Dispatch                  │
└──────┬──────────┬──────────────┬──────────────────┬──────────────┘
       ▼          ▼              ▼                  ▼
┌──────────┐ ┌──────────┐ ┌─────────────┐ ┌───────────────┐ ┌──────────────┐
│Runtime   │ │Vision    │ │Debug        │ │UxPipeline     │ │Game Systems  │
│Tools     │ │          │ │             │ │(live + visual)│ │+ Custom      │
├──────────┤ ├──────────┤ ├─────────────┤ ├───────────────┤ ├──────────────┤
│SceneTree │ │Screenshot│ │Perf/Engine  │ │Live-Controls  │ │Audio (6)     │
│Klicks    │ │Pixel     │ │ClassDB      │ │(exakte Labels)│ │Animation (7) │
│Keys      │ │Color     │ │Files/Log    │ │Pixel-Analyse  │ │Gamepad (4)   │
│Motion/   │ │Template  │ │EventLog     │ │Watch-Clock    │ │Shader/Net(4) │
│Drag      │ │Detect    │ │Memory       │ │Log-Anomalien  │ │Freeze/Step(5)│
│Eval      │ │Grid      │ │             │ │E2E-Anbindung  │ │custom_* API  │
│Freeze/   │ │OCR-Worker│ │             │ │               │ │Goal(3)       │
│Step      │ │(Tesseract)│ │             │ │               │ │Analyze(4)    │
└──────────┘ └──────────┘ └─────────────┘ └───────────────┘ └──────────────┘
```

**E2E-Suite (2 Tools, `runtime/tools/e2e/`)** + **PlaythroughDriver
(`testing/e2e/mcp_playthrough_driver.gd`)**:
sichtbare Playability-Szenarien (MainMenu → World → TechMenu → Pause/Save/Menu →
Freeze/Step → Goal/Code-Analyze), konsumieren dieselben Tool-Calls wie ein
externer Agent, sammeln EventLog-Anomalien.

**Agent-Workflow (`AGENT_WORKFLOW.md`)**:
6-Schritte-Loop für autonome Agents: Archiv lesen → Projekt analysieren → Scripts schreiben → testen → archivieren → nächste Session.

**Live-Spieler-Handoff (`PLAYTEST_HANDOFF.md`)**:
Verbindlicher Vertrag für sichtbares Remote-Gameplay. Pro Ingame-Aktion genau ein separater MCP-Tool-Call; keine direkte GameState-Mutation und keine Goal-/Chain-Orchestrierung als Spielerersatz. Game-Mismatch, MCP-Mismatch und Diagnoseunsicherheit werden getrennt protokolliert.

**Client (`client/`)**:
- `agent_repair_loop.py` — Autonomer Repair- & Feature-Orchestrator für geschlossene Self-Healing-Läufe
- `mcp_client.py` — Referenz-TCP-Client für Metadaten, Artefakte und Worker-Aufträge (interaktiv/auto/one-shot)
- `vision_worker.py` + `vision_worker.js` — lokale Bildanalyse-Instanzen (ohne Base64-Roundtrip; lesen
  die Context-Artefakte aus `user://mcp_context`); JS-Worker enthält **echtes OCR via Tesseract.js**
- `remote_playout.py` — Remote-Playthrough über `runtime_ux_*` (agentengleich)
- `mcp_file_driver.js` (`playthroughs/atomic/`) — **Standard-Transport für wiederholte sichtbare Läufe**: ein persistenter Prozess, ein Handshake pro Lauf, ein Tool-Call pro Befehlszeile (Datei-Queue statt Prozess-Neustart). Latenz ~4–16 ms pro Call statt 1–2 s Prozess-/Handshake-Overhead + ~30 s Hang durch zuvor unaufgeräumte Client-Timer (`mcp_lib.js` cleart die Timeouts jetzt in `settle()`).

**MCP Resources (`resources/list`, `resources/read`)**:
- `godot://scene/current` — Autoritative Live-Szenenhierarchie & Controls
- `godot://logs/recent` — Letzte Engine- & MCP-Logs / Anomalien
- `godot://gameState/summary` — Wirtschafts-, Forschungs- & Flottenübersicht
- `godot://test/results` — Letzter ausgeführter Chain-Trace & Evidenz

---

## Server-Lifecycle & Taktrate

| Phase | Bedeutung |
|---|---|
| STOPPED → BOOTING | `start_server()` läuft an |
| LISTENING | TCP lauscht / stdio-Reader gestartet |
| READY | Client kann Tools callen |
| BUSY | async Tool in Arbeit; weitere async Tools queuen sich |

- **`PROCESS_MODE_ALWAYS`** auf Host + Server: Polling läuft auch bei
  `get_tree().paused = true` (Pause-Menü) weiter — Remote-Testing bleibt aktiv.
- **Async-Queue**: await-Tools (wait_ms, wait_for_stable, e2e_run) werden
  serialisiert — kein paralleler Zwischenzustand.
- **`runtime_mcp_status`**: Zustand, Uptime, Tool-Latenz (avg/max), letzte
  Events, Watch-Status, Kontext-Cache — für "navigiere mich durch dein Leben".

## Session-Profile (Play-Goal-Gate)

Der verbindliche Spieler-Vertrag (`PLAYTEST_HANDOFF.md`) wird seit v4.1 nicht
mehr nur dokumentiert, sondern vom Server erzwungen (`runtime/autonomy/mcp_contract_gate.gd`):

| Profil | Bedeutung | Gesperrte Tools (Auswahl) |
|---|---|---|
| `player` (Standard) | sichtbarer Spieler-Lauf: ein Atom pro Call, UI-Aktionen, read-only | `runtime_goal_*`, `runtime_chain_run`, `runtime_eval`, `runtime_ux_click`, `game_state_restore`, `runtime_freeze/step*`, `runtime_e2e_run`, Autonomy-Writes |
| `qa` | Debug/QA: Goal Player, Chains, Freeze/Step, E2E | wie player, aber diese freigeschaltet |
| `dev` | Reparatur/Edit: alles aus qa + `runtime_eval` (unter `--mcp-developer`) | — |

Wahl: CLI `--mcp-profile=qa|dev` oder Editor-Dock „Play-Goal“ (wird nach
`user://gdscript_mcp_profile.cfg` geschrieben und beim Runtime-Boot gelesen).
Verstöße werden als `contract_violations` in `runtime_mcp_status` gezählt und als
Lifecycle-Event (Kategorie `contract`) protokolliert — kein Endlos-Contract-Bruch.
**Headless** verweigert der Server weiterhin absolut (kein Renderer → kein MCP).

## Projektagnostische Integration

Das Add-on funktioniert ohne fest verdrahtete Projekt-ID, Szenenpfade oder
`GameState`-Implementierung. Optional können Projekte in `project.godot` folgende
Settings setzen:

```ini
[application]
mcp/game_state_node="/root/MyGameState"
mcp/event_log_node="/root/MyEventLog"
mcp/project_adapter_node="/root/MyMcpProjectAdapter"
mcp/game_state_script="res://scripts/my_game_state.gd"
```

Ohne diese Settings verwendet MCP nur generische Godot-Funktionen und sucht
konventionelle Node-Namen (`GameState`, `EventLog`, `PlanetField`,
`WorkerManager`) als best-effort Fallback. Die Projekt-ID wird aus
`application/config/name` abgeleitet; es gibt keinen Default auf einen konkreten
Spielnamen.

### Automatische Selbst-Registrierung (seit Plugin-Aktivierung)

Das Add-on richtet sich beim Aktivieren in **Project Settings → Plugins** selbst
im aktuellen Projekt ein — ohne manuelle `project.godot`-Editierung. Beim ersten
Editor-Boot (`_register_project_integration()` in `editor/gdscript_mcp_plugin.gd`)
ergänzt es idempotent:

1. **Autoloads** (nur wenn fehlend): `McpRuntime` →
   `res://addons/gdscript_mcp/runtime/host/mcp_runtime.gd` und
   `McpProjectAdapter` →
   `res://addons/gdscript_mcp/runtime/core/mcp_project_adapter.gd`.
   Beide sind als Autoloads **inert**: ohne den Start-Flag `--mcp` kehrt
   `_ready()` früh zurück und es startet kein MCP-Server.
2. **`application/mcp/*`-Settings** (nur wenn fehlend):
   `preflight_script`, `main_menu_scene`, `game_state_node`,
   `event_log_node`, `project_adapter_node`, `game_state_script`.

Die Registrierung schreibt `project.godot` nur bei tatsächlicher Abweichung —
reine Starts bei bereits konfiguriertem Zustand hinterlassen keinen Dirty-State.

### Zwei SnipWar-Defaults (überschreibbar!)

Nur `preflight_script` und `main_menu_scene` tragen SnipWar-Defaults, damit das
Add-on in SnipWar out-of-the-box läuft. Andere Projekte **überschreiben sie in
eigener `project.godot`**:

```ini
[application]
mcp/preflight_script="res://addons/mein_plugin/tests/preflight.gd"
mcp/main_menu_scene="res://scenes/start/start_screen.tscn"
```

- `preflight_script` wird vom `preflight_constraint`-Chain-Schritt als Headless-
  Subprozess gestartet (siehe `runtime/autonomy/mcp_chain_controller.gd`).
- `main_menu_scene` lädt der sichtbare Playthrough-Driver
  (`testing/e2e/mcp_playthrough_driver.gd`).

Werden sie leer gelassen bzw. nicht gesetzt, fallen beide Resolver auf die
SnipWar-Defaults zurück (`res://scripts/preflight.gd` bzw.
`res://scenes/main_menu/main_menu.tscn`).

### Einbindung ohne SnipWar (Schritt für Schritt)

1. Plugin-Ordner unter `res://addons/gdscript_mcp/` ablegen (Kopie, submodule
   oder Packaged Release). Das gut bekannte `addons/gdscript_mcp`-Verzeichnis ist
   erwartet — intern sind alle `res://addons/...`-Pfade addon-intern und
   redlicherweise an diesen Well-known-Pfad gebunden.
2. In **Project Settings → Plugins**: `GDScript MCP Bridge` aktivieren. Das
   Add-on registriert nun automatisch Autoloads + `application/mcp/*`-Settings.
3. Optional eigene Werte für `application/mcp/preflight_script` und
   `application/mcp/main_menu_scene` setzen (falls dein Projekt eigene
   Test-/Startpfade nutzt).
4. Falls du GameState-/EventLog-Brücken nutzt: `mcp/game_state_node`,
   `mcp/event_log_node` bzw. `mcp/game_state_script` setzen. Ohne diese liefert
   MCP nur generische Runtime-/Vision-/UX-Tools (voll funktionsfähig, aber ohne
   spielspezifische State-Fingerprints).
5. Sichtbaren Runtime starten: `$GODOT_BIN --path . -- --mcp --mcp-port 9090`.
   SnipWar-Preflight/Constraints bleiben in SnipWar und werden nie in den
   Addon-Kern gezogen.

## Editor ↔ Ingame-Wechsel

- `editor_run_project` — startet das Projekt aus dem Editor; `with_mcp=true`
  aktiviert Runtime-MCP im selben Godot-Prozess (in-process). Ein eigenständiger
  Spielstart kann alternativ über `-- --mcp` erfolgen; Ports sind konfigurierbar
  und nur Defaults, keine Projektannahmen.
- `editor_logs_read` — Editor-Session-Logs (Lifecycle-Cursor) + optionaler
  Engine-Log-Tail (`--log-file` beim Editor-Start), analog zu HiGodots `logs_read`.
- Schreib-Gate vereinheitlicht: „Allow editor write actions" im Dock aktiviert
  jetzt BOTH die `editor_*`-Mutationen UND die Autonomy-Workspace-Tools
  (`runtime_autonomy_write/patch/export`) — vorher blieben die Autonomy-Tools im
  Editor-Modus trotz aktiviertem Gate gesperrt.

## Tool-Liste (Stand: 107 Tools + custom_*)

### Runtime (19) — `runtime/tools/runtime/mcp_runtime_tools.gd`
| Tool | Beschreibung |
|---|---|
| `runtime_get_scene_tree` | begrenzter Szenenbaum mit `root_path`, `max_depth`, `max_nodes` |
| `runtime_scroll` | eine sichtbare virtuelle Mausrad-Geste über Pfad oder Koordinate |
| `runtime_find_node` | Node per Pfad |
| `runtime_click` | Engine-Klick (press→release belegt, Motion 1 Frame davor; `inject_mode` auto/push/parse; Koordinaten = Viewport-Pixel/Absolute) |
| `runtime_drag` | Drag-Geste (press→motion→release über virtuelle Mausposition) |
| `runtime_key` | Taste (keycode + physical_keycode) |
| `runtime_mouse_move` | Hover-Motion. Default: **smooth sichtbarer Cursor-Travel** (mehrere interpolierte Frames, kein Teleport) über `smooth`/`duration_ms`; auch `runtime_click` nähert sich standardmäßig sanft an |
| `runtime_virtual_mouse_status` | Virtuelle Maus: active, Block-Status, Position, Bounds, blockierte physische Events |
| `runtime_get_ui_state` | UI-Zustand (Text, Rect, Focus, Disabled) |
| `runtime_wait_frames` | N Frames warten |
| `runtime_wait_ms` | N ms warten (Timer, nicht Frames; Pause-tolerante Engine-Uhr) |
| `runtime_eval` | GDScript-Ausdruck |
| `runtime_inspect_node` | Properties/Signals/Children |
| `runtime_find_nodes_by_type` / `runtime_node_ancestry` | Klassensuche / Parent-Kette |
| `runtime_freeze` / `runtime_unfreeze` | Pause-/Resume des Game-Trees (deterministische Steuerung) |
| `runtime_step_frame` | Genau 1 Frame im Freeze-Modus, dann re-freeze |
| `runtime_step_frames` | N zusammenhängende Frames (Tweens/Scene-Transitions laufen durch), dann re-freeze |
| `runtime_freeze_status` | Freeze-Zustand, geframte Schritte, pending Inputs |
| `runtime_camera_move_to` | MapCamera per Tween zu x,y bewegen (optionale zoom/duration) |

**Klick-Koordinaten**: `runtime_click` reicht Positionen in Viewport-Koordinaten.
`path`≠"" und x/y=-1: Zentrum des Controls wird per `get_global_rect()` aufgelöst.
`inject_mode=parse` transformiert über die Window-Screen-Transform (skalierte
Viewports: siehe Engine-Forum "scaled viewports click"; Godot rechnt
`Input.parse_input_event` in Screen-Coords). Netzwerk-Fokus benötigt kein OS.

### Vision (22) — `runtime/tools/vision/`
`runtime_screenshot` schreibt ein Session-lokales Bildartefakt und liefert nur
Metadaten (`context_id`, lokaler Pfad, Dimensionen, Ablaufzeit). Pixel/Color/
Template/Edge/Text/Grid-Tools arbeiten auf dem letzten In-Memory-Frame; externe
Python/Node-Worker lesen die Artefakte direkt von Disk.

**Bildpfad:**
1. **Lokales Artefakt** unter dem Session-Context-Root, getrennt für Runtime und
   Editor, mit TTL/Record-Limit/Byte-Limit.
2. **Worker-Verarbeitung** liest dieses Artefakt direkt über `context_id`; die
   MCP-Antwort enthält keine Screenshotbytes.
3. **`agent_context`** liefert zusätzlich ein kompaktes Text-Transkript der UI
   mit Szene, exakten Labels und Screen-Koordinaten.
4. **Explizite Freigabe:** `runtime_context_release` löscht einzelne Artefakte;
   `runtime_context_cleanup` und der Lifecycle-Tick entfernen abgelaufene Daten.

Template-Tools akzeptieren weiterhin bewusst ein vom Agenten bereitgestelltes
Template als Eingabe; das ist getrennt vom Screenshottransport.

**OCR-Beschleunigung:** Worker-Pool (default 2, env `MCP_OCR_POOL`) verarbeitet
OCR-Jobs parallel (round-robin, Serve-Loop awaited nicht seriell); `cacheMethod "write"` +
lokaler `cachePath` (`node_modules/.cache/tesseract.js`, inkl. einmalig abgelegter
`deu.traineddata.gz`) machen den Kaltstart komplett lokal (~2 s statt CDN-Download).
Kein `workerPath` setzen (Browser-Variante crasht in Node — tesseract.js wählt sonst
automatisch die Node-kompatible Worker-Variante).

**PFLICHT: Bild-/OCR-Analyse bei unerwartetem Ergebnis — ENTKOPPELT** — Der
Runtime-Server (`mcp_server.gd`) erkennt unerwartete Tool-Antworten (Fehler
`ok:false`/`_error`/„Node not found", `clicked:false`, `moved:false`, `controls:[]`)
und antwortet **sofort** mit `visual_evidence: {status: "pending"}` — die Aktion
blockiert NIE auf Screenshot/OCR. Die Analyse (Screenshot + OCR) läuft als
Fire-and-forget im Hintergrund in einen Cache (`_evidence_cache`); der Agent holt
sie gezielt über das neue Host-Tool **`runtime_visual_evidence`** ab:
`{"wait_ms": 3000}` pollt eine laufende Analyse (0 = sofortiger Stand),
`{"capture": true}` startet frisch, wenn nichts gecacht ist. Antwort:
`{status: none|pending|ready, evidence: {screenshot, ocr}}`. Rekursionsschutz:
Screenshot-/Analyse-/Vision-/Status-Tools sind ausgenommen.

### Debug (12) — `runtime/tools/debug/`
Perf, Rendering, Engine-Info, Frame-Timing, Projekt-Config, Files, ClassDB,
Resource-UID, EventLog, Object-Counts, Memory, Profiling.

### UX-Pipeline (10) — `runtime/tools/ux/`
- `runtime_ux_analyze` — vollständige Analyse (Live + visuell) inkl. kompakter `perf`-Werte (FPS, Draw-Calls, Objekte, Nodes, Process-MS) für Reaktionsfähigkeits-Checks
- `runtime_ux_scan` — nur Live (Fast-Path), standardmäßig begrenzter Scope mit `root_path`, `max_controls`, `max_depth`
- `runtime_ux_find` — Element per Text/Name/Typ in begrenztem Scope (exakte Labels aus der sichtbaren UI)
- `runtime_ux_read` — Text-Hint aus Region
- `runtime_ux_click` — Find + Klick in einem Call
- `runtime_ux_watch_start` / `stop` / `state` / `snapshot` — periodische
  Live-Snapshots, **ereignisgesteuert** (Signatur-Delta aus sichtbaren Controls)
- `runtime_ux_logs` — EventLog-Einträge + Anomalien (error/warning) für
  Auffälligkeit-Lokalisierung während E2E-Läufen

### Game Systems (24) — `runtime/tools/systems/mcp_audio_tools.gd`
Agent kann echte Spielsysteme steuern (Audio, Animation, Network, Gamepad/Touch,
Shader, Partikel):
| Kategorie | Tools |
|---|---|
| Audio (6) | `runtime_audio_play`, `_stop`, `_bus_info`, `_set_volume`, `_list_streams`, `_set_stream` |
| Animation (7) | `runtime_animation_list`, `_play`, `_stop`, `_seek`, `_get_info`, `_tree_travel`, `_tree_set_param` |
| Gamepad/Touch (4) | `runtime_gamepad_button`, `_axis`, `runtime_touch_event`, `_drag` |
| Shader/Particles (2) | `runtime_shader_set_param`, `runtime_particles_config` |
| Network (5) | `runtime_network_create_server`, `_create_client`, `_disconnect`, `_get_peers`, `_send_rpc` |

### Autonomy Workspace (Slice D) — `runtime/autonomy/mcp_capability_planner.gd`
Journaled edit-workspace tools for autonomous repair. **Write-gated**: all mutating
tools stay blocked until the host enables them (`--mcp-autonomy-writes`); every write
lands in an isolated `user://mcp_workspaces/run_*` sandbox with preimage/hash journaling
and explicit rollback. Probes remain read-only regardless of the gate.

| Tool | Access | Beschreibung |
|---|---|---|
| `runtime_autonomy_workspace_begin` | write | Journaled run workspace starten (Sandbox + Baseline-Fingerprint) |
| `runtime_autonomy_workspace_status` | read | Zustand, Baseline- und Transaktionszahlen |
| `runtime_autonomy_workspace_files` | read | Dateien im Workspace auflisten |
| `runtime_autonomy_workspace_baseline` | read | Workspace gegen Start-Baseline prüfen |
| `runtime_autonomy_workspace_end` | read | Run abschließen (verweigert offene Transaktionen) |
| `runtime_autonomy_read` | read | res://-/user://-Datei mit Hash + Bytecount lesen |
| `runtime_autonomy_write` | write | Journaled Write, nur innerhalb Workspace-Root |
| `runtime_autonomy_patch` | write | Fail-closed Single-Occurrence-Patch |
| `runtime_autonomy_search` | read | Textsuche über Workspace-Dateien |
| `runtime_autonomy_symbols` | read | GDScript-Klassen/Funcs/Vars/Consts erkennen |
| `runtime_autonomy_rollback` | write | Einzelne Transaktion zurücksetzen |
| `runtime_autonomy_rollback_all` | write | Alle Transaktionen zur Baseline zurücksetzen |
| `runtime_autonomy_workspace_import` | write | res://-Datei in Workspace kopieren (Origin-Hash registriert) |
| `runtime_autonomy_export` | write | Gated Export: validierte Änderung zurück nach res:// (apply=true nötig, dry-run default) |
| `runtime_autonomy_imports` | read | Importierte Dateien auflisten |

**Export-Gate:** `runtime_autonomy_export` schreibt nie ohne explizites `apply=true`; es validiert
GDScript-/JSON-Inhalt, verweigert bei verändertem Origin (Hash-Mismatch, es sei denn `force=true`)
und legt vor dem Schreiben ein externes Journal-Preimage an — `runtime_autonomy_rollback`
stellt den `res://`-Pfad danach wieder her.

### Custom Tools API — `runtime/core/mcp_custom_tool_loader.gd`
Jede `.gd` in `res://mcp_tools/` wird beim Laden automatisch registriert:
`get_tool_defs()` + `dispatch_tool()` implementieren, erscheint als `custom_*`-Tool,
Hot-Reload bei jedem `get_all_tools()`. `dispatch_async` wird unterstützt.

### Goal Player (4) — `runtime/tools/e2e/mcp_goal_player.gd`
Diese Tools gehören zum automatisierten E2E-/Diagnosemodus und sind **kein** sichtbarer Spieler-Workflow. Für Live-Remote-Gameplay sind `runtime_goal_play`, `runtime_goal_sequence` und `runtime_chain_run` gesperrte Abkürzungen, weil sie mehrere Spielaktionen planen oder ausführen können.
- `runtime_goal_play` (async) — automatisierter E2E-/Diagnose-Loop
- `runtime_goal_sequence` (async) — automatisierte Folge; nicht als Spielerersatz verwenden
- `runtime_goal_check` — read-only Zielausdruck einmal auswerten
- `runtime_goal_history` — letzte automatisierte Schritte inspizieren

### Chain Controller (3) — `runtime/autonomy/mcp_chain_controller.gd`
Deklarative Kettenschritt-Orchestrierung für kombinierte Headless- und Visible-Testläufe:
- `runtime_chain_validate` — Kette vor Ausführung auf Atomgrenzen, sichtbare Verbote, Screenshot-Gründe und Context-Limits prüfen
- `runtime_chain_run` (async) — validierte Kette aus Preconditions, Tools, Assertions und Evidenzerfassung ausführen
- `runtime_chain_trace` — Letzten Ausführungs-Trace und Teilschritt-Verdicts abfragen

Neuer `preflight_constraint`-Schritt: startet das Preflight-Skript als Headless-
Subprozess und pollt das `--mcp-json`-Ergebnis (`user://mcp_preflight_result.json`).
Der Pfad ist konfigurierbar (`application/mcp/preflight_script`, Default
`res://scripts/preflight.gd`). Kein Platzhalter — ein „PASS" für ein Constraint ist
nur echt, wenn die Preflight-Suite es wirklich bestätigt hat.

### Code Analyzer (4) — `runtime/tools/e2e/mcp_code_analyzer.gd`
Statische Projektanalyse über Dateisystem + FileAccess:
- `runtime_analyze_project` — input_methods, signals, scenes, autoloads, GameState-API, custom MCP tools
- `runtime_analyze_input` — `_input`/`_unhandled_input`/`is_action_pressed`-Treffer pro Datei
- `runtime_analyze_signals` — alle GDScript-Signal-Deklarationen
- `runtime_analyze_game_state` — öffentliche Methoden der GameState-API

### E2E (2) — sichtbare Playability-Szenarien (`runtime/tools/e2e/mcp_e2e.gd`)
`runtime_e2e_list`, `runtime_e2e_run` (async). Szenarien: `main_menu`,
`new_game_to_world`, `pause_save_menu`, `virtual_mouse_edges`, `freeze_step`,
`analyze_and_goal` (Goal-Player + Code-Analyzer).

> **Doktrin:** Die Tech-Menü-Szenarien (`tech_menu_open_close`, `research_start`)
> wurden entfernt, weil das Technologie-Seitenpanel durch den Dossier-Hub
> (Planeten-Dossier [P], Werkstatt [W], Forschungsbaum [F]) ersetzt wurde. Neue
> UI-Flows werden NICHT als vordefinierte E2E-Szenarien hartkodiert: MCP-Agenten
> entdecken die Oberfläche von Grund auf über `runtime_ux_*`, verifizieren gegen
> GameState-Signale und persistieren gewonnene Abläufe als erweiterte Bibliothek
> ins Playthrough-Archiv (`runtime_playthrough_success`).

### Playthrough-Archiv (8) — `runtime/tools/e2e/mcp_playthrough_tools.gd`
Lokale Erfolgs-/Kontext-DB (`user://mcp_playthrough/playthrough.jsonl`,
PNG-Frames `frames/`, Presets `snapshots/*.tres`) für autonomes Weiterspielen:
- `runtime_playthrough_success` — erfolgreiche Aktion speichern (Frame + Preset automatisch)
- `runtime_playthrough_search` / `latest` / `stats` — Aktionen durchsuchen/fortsetzen
- `runtime_playthrough_frames` — PNG-Pfade der letzten Schritte (code+bild-basis)
- `runtime_playthrough_preset_load` — `restore_run()`: reproduzierbare Situation
- Nach jedem E2E-PASS archiviert `McpE2E` das Szenario automatisch als Erfolg (+Preset)

## E2E & Playability (Remote-Testing)

Die sichtbare Spielererkundung ist kein Gesamt-E2E-Skript: Nach jedem einzelnen MCP-Atom wird neu beobachtet und entschieden. `mcp_playthrough_driver.gd`, `runtime_e2e_run`, `runtime_goal_sequence` und `runtime_chain_run` bleiben für Contract-/Diagnosemodi getrennt und dürfen keinen Live-Spieler-PASS begründen. Siehe `PLAYTEST_HANDOFF.md`.

```bash
# Playthrough sichtbar im Spielfenster (voll Renderer, kein Headless):
$GODOT_BIN --path . --script res://addons/gdscript_mcp/testing/e2e/mcp_playthrough_driver.gd
$GODOT_BIN --path . --script ... --mcp-e2e=new_game_to_world
$GODOT_BIN --path . --script ... --mcp-e2e-list

# Denkbar synchron: Server im Spiel + remote_playout.py:
# Spiel:   $GODOT_BIN --path . -- --mcp --mcp-port 9090
# Agent:   python client/remote_playout.py --port 9090 --flow full
```

E2E-Ergebnis enthält `steps[]` + `anomalies[]` (EventLog-Fehler/Warnungen
während des Laufs) — während der Tests sofort auf Auffälligkeiten prüfbar.

Ein sichtbarer Live-Run dokumentiert zusätzlich separat: `game_findings`, `mcp_findings`, `diagnostic_uncertainty` und den genauen Atom-Trace. Ein Transportfehler ist kein Game-Failure; ein sichtbarer UI-/State-Widerspruch ist kein MCP-Failure.

**Performancevertrag:** Screenshots sind Evidenz bei Unklarheit, nicht der Standard vor jeder Aktion. Für viele atomare Aktionen wird eine persistente MCP-Verbindung empfohlen; sie spart neue Prozesse und Handshakes, ohne mehrere Ingame-Tools in einem Atom zu bündeln. Identische Live-Scans werden über Watch-/Snapshot-Zustände wiederverwendet. Chains müssen vor Ausführung `runtime_chain_validate` passieren und pro Schritt genau einen MCP-Tool-Call, bounded context, Postcondition und No-progress-Grenze enthalten.

## Schnellstart

**Variante A — Plugin (empfohlen):** Plugin in den Project Settings aktivieren
(das Add-on registriert Autoloads + `application/mcp/*` selbst), optional
Settings setzen, dann sichtbaren Runtime starten.

**Variante B — rein CLI, ohne Plugin-Ordner-Auto-Setup:** Autoloads müssten
manuell in `project.godot` unter `[autoload]` stehen (siehe Selbst-Registrierung),
dann:

```bash
# 1. Spiel mit MCP starten (sichtbares Fenster)
$GODOT_BIN --path . -- --mcp --mcp-port 9090 --mcp-transport tcp

# 2. Connecten (Python, Runtime-TCP):
python addons/gdscript_mcp/client/mcp_client.py --port 9090 --one-shot
# Für viele atomare Aktionen: einen persistenten Socket/Handshake nutzen
node addons/gdscript_mcp/client/playthroughs/atomic/atomic_session.js
# stdin: eine JSON-Zeile pro MCP-Call, z. B. {"tool":"runtime_ux_scan","args":{"max_controls":120}}
# Empfohlen für viele atomare Aktionen — direkte Ausführung über mcp_file_driver
# (ein Prozess + Handshake pro Lauf, eine Zeile = genau ein MCP-Call):
MCP_PORT=9090 MCP_COMMANDS=/tmp/mcp_cmds.jsonl MCP_OUTPUT=/tmp/mcp_out.jsonl\
  node addons/gdscript_mcp/client/playthroughs/atomic/mcp_file_driver.js
echo '{"tool":"runtime_ux_scan","args":{}}' >> /tmp/mcp_cmds.jsonl   # Befehle anhängen
tail -1 /tmp/mcp_out.jsonl                                            # eine Ergebnis-Zeile pro Befehl
echo '{"command":"close"}' >> /tmp/mcp_cmds.jsonl                     # sauber beenden

# 3. Lifecycle abfragen:
#    initialize → initialized → tools/call runtime_mcp_status
```

## Fallstricke & Godot-4.7-Hinweise

- **Headless**: Vision/UX nur mit echtem Renderer (Dummy-Renderer liefert keine
  echten Screenshots, `get_image()` crasht bei null RID).
- **`InputEventKey`**: keycode + physical_keycode beide setzen.
- **Klick-Release**: Release wird um Frames (default 1) verzögert; Control
  registriert komplette Press→Release-Geste.
- **TCP**: funktioniert als separater Prozess nur, wenn das Spiel normal
  (nicht via `--script`) läuft, `StreamPeerTCP.connect_to_host()` bleibt im
  `--script`-Modus hängen (bekannt aus Preflight/Server-Doku).
- **StringName vs String**: Dictionary-Keys in `.tres` bleiben StringName;
  MCP-Tools konvertieren nach String.
- **`runtime_wait_ms`** nutzt `create_timer(ms/1000, true)` — Pause-ignorant,
  konsistent mit dem ALWAYS-Lifecycle.
- **Bildexport**: Lokales Artefakt + kompakte Metadaten; keine Screenshotbytes im MCP-Result.
- **UID-Sidecars**: neue `.gd`-Dateien brauchen `.gd.uid` (versioniert).

## Dateiübersicht (nach Rollen gruppiert)

```
addons/gdscript_mcp/
├── runtime/
│   ├── core/mcp_tool_registry.gd        Registry + Routing
│   ├── lifecycle/mcp_lifecycle.gd       Server-Lifecycle (eigener Zustand)
│   ├── protocol/mcp_protocol.gd         JSON-RPC/Content-Formatter
│   ├── host/
│   │   ├── mcp_server.gd                Server-Host (Transport, Queue, Status)
│   │   └── mcp_runtime.gd               Autoload (--mcp CLI opt-in)
│   ├── context/mcp_context_store.gd     Lokale Bild-Artefakte (TTL, Limit)
│   ├── core/mcp_project_adapter.gd      Optional cross-project adapter
│   ├── core/mcp_custom_tool_loader.gd   Custom Tools (res://mcp_tools/, hot-reload)
│   └── tools/
│       ├── runtime/ ...  Debug/ ...      Runtime/Input, Vision, Debug, UX, E2E
│       ├── vision / mcp_vision_worker.gd Node/Python-Worker-Supervisor
│       ├── debug/     ...
│       ├── ux/        ...  mcp_ux_live, mcp_ux_pipeline, mcp_ux_*,
│       ├── e2e/       mcp_e2e.gd, mcp_goal_player.gd, mcp_code_analyzer.gd, mcp_playthrough_tools.gd
├── AGENT_WORKFLOW.md                  Agent-Workflow-Doku (6-Schritte-Loop)
│       └── systems/   mcp_audio_tools.gd  (Audio, Animation, Network, Gamepad, Shader, Partikel)
├── client/  (mcp_client.py, vision_worker.py, vision_worker.js, remote_playout.py, agent_store.py, agent_playthrough.py, mcp_stresstest.js)
├── editor/  (Plugin + Dock — Pipeline-Visualisierung für den User: Agent-Ziel,
│             Tool-Call-Feed mit Timing/Fehlern, OCR-Evidence, Event-Stream; KEINE
│             Agenten-Steuerung mehr — die Aktionen macht der Agent über MCP)
└── testing/ (mcp_test_runner, mcp_test_scenario, scenarios/, e2e/playthrough_driver)
```