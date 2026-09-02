# MCP Agent Workflow — Autonome Playtesting-Umgebung

**Stand:** 2026-08-26
**Ziel:** Unkomplizierte, umfassende Autonomie für Agents, die mit jeder Benutzung schneller und präziser wird — unabhängig vom konkreten Godot-Projekt.

> **LIVE-SPIELERREGEL:** Sichtbares Gameplay wird ausschließlich als einzelne MCP-Atome ausgeführt. Ein Atom-Script macht genau einen MCP-Tool-Call. Der Agent liest nach jedem Call die Live-Oberfläche und entscheidet den nächsten Zug erst danach. Keine direkte GameState-Mutation, kein `runtime_goal_sequence`, kein `runtime_goal_play`, kein `runtime_chain_run` und kein vorgeplanter Gesamt-Runner für sichtbare Spielerläufe. Der vollständige Vertrag, die Atom-Registry und die Handoff-Findings stehen in `PLAYTEST_HANDOFF.md`.

## Modi strikt trennen

- **Live-Spieler:** `runtime_ux_scan`/`runtime_ux_find` → `runtime_mouse_move` → optionaler Scan → `runtime_click`/`runtime_scroll` → separater Wait/Scan. Jeder Schritt ist ein eigener MCP-Call; für viele Schritte darf der Transport persistent bleiben.
- **Autonomie-Repair:** Workspace, Write-Gate, Export und Rollback; kein Gameplay-Nachweis.
- **Vertragstest:** Headless oder sichtbare Test-Suite; kein Spieler-PASS. Chains zuerst validieren, dann in begrenzten Segmenten ausführen.
- **Editor-Tooling:** Editor-Port/Dock, Undo/Redo und Editor-Schreibrechte; kein Runtime-Gameplay-PASS.


---

## Installation & Selbst-Registrierung (projektagnostisch)

Das Add-on ist projektagnostisch: Es koppelt keine SnipWar-Logik ein und richtet
sich beim Aktivieren **automatisch im aktuellen Godot-Projekt** ein — kein
manuelles Einfügen in `project.godot` nötig.

### Wie aktivieren

1. Ordner unter `res://addons/mcp/` ablegen (Kopie / submodule /
   packaged Release).
2. **Project Settings → Plugins**: `GDScript MCP Bridge` aktivieren.
3. Beim nächsten Editor-Boot registriert das Plugin idempotent (nur fehlende):
   - Autoloads `McpRuntime` + `McpProjectAdapter` (inert ohne `--mcp`-Flag),
   - `application/mcp/*`-Settings (`preflight_script`, `main_menu_scene`,
     `game_state_node`, `event_log_node`, `project_adapter_node`,
     `game_state_script`).

### `application/mcp/*`-Settings (Defaults vs. projektseitig)

| Setting | Default | Zweck |
|---|---|---|
| `preflight_script` | `res://scripts/preflight.gd` (SnipWar) | Pfad des Preflight-Tests für den `preflight_constraint`-Chain-Schritt |
| `main_menu_scene` | `res://scenes/main_menu/main_menu.tscn` (SnipWar) | Start-Szene des sichtbaren Playthrough-Driver |
| `game_state_node` | leer (= auto) | Pfad zum spielspezifischen GameState-Node, falls vorhanden |
| `event_log_node` | leer (= auto) | Pfad zum EventLog-Node, falls vorhanden |
| `project_adapter_node` | leer (= auto, `/root/McpProjectAdapter`) | optionaler Projekt-Adapter |
| `game_state_script` | leer (= auto/Scan) | Skript-Pfad für GameState-API-Analyse |

Die beiden SnipWar-Defaults erlauben SnipWar out-of-the-box, sind aber nur
Fallbacks: Ein anderes Projekt setzt eigene Werte in **seiner** `project.godot`
und vermischt so nie SnipWar-Constraints mit dem Addon. SnipWars
`scripts/preflight.gd` wird nur als optional konfigurierbarer Chain-Schritt genutzt
und nie in den Addon-Kern gezogen.

### Ohne SnipWar nutzen

1. Plugin aktivieren (siehe oben) — Autoloads/Settings kommen automatisch.
2. Optional `application/mcp/preflight_script` + `main_menu_scene` auf eigene
   Pfade setzen (oder weglassen → generische Tools, die ohne Spiel allein
   funktionieren).
3. Optional `mcp/game_state_node`/`event_log_node`/`game_state_script` für
   State-/Log-Brücken setzen; fehlen sie, degradiert MCP clean (leere
   Capabilities) statt zu crashen.
4. Sichtbaren Runtime starten: `$GODOT_BIN --path . -- --mcp --mcp-port 9090`.

---

## Kernprinzip

Jeder Agent speichert seine funktionierenden Scripts atomar, kategorisiert sie und hinterlässt Wissen im `index.jsonl`-Archiv. Der nächste Agent liest dieses Archiv und nutzt vorhandene Lösungen statt null-deriviert zu analysieren.

---

## Workflow (6 Schritte)

### Schritt 1: Archiv lesen (5 Sekunden)
```bash
# Vorhandene Scripts laden:
# → index.jsonl in user://mcp_playthrough/scripts/
# → Kategorien: runtime, gameplay, e2e, ux, fix
# → Jeder Eintrag: name, category, verdict, session, path, tested_with, description
```
**Frage an sich selbst:** "Gibt es ein Script das mein Problem bereits löst?"

### Schritt 2: Projekt analysieren (30 Sekunden)
```
runtime_analyze_project   → Szenen, Autoloads und verfügbare MCP-/State-APIs
runtime_analyze_input     → _input/_unhandled_input Treffer
runtime_analyze_game_state → konfigurierte oder erkannte State-Skripte/öffentliche Methoden
```
**Frage:** "Welche Lücken gibt es die mein Archiv nicht abdeckt?"

### Schritt 3: Scripts schreiben oder fixen (variabel)
- **Neues Script:** In `user://mcp_playthrough/scripts/<name>.gd` schreiben
- **Bestehendes Script fixen:** Kopie anlegen, fixen, altes Archivieren
- **Atomar:** Jedes Live-Action-Script darf genau einen MCP-Tool-Call ausführen. Transport, Zielsuche, Hover, Klick, Wait, Scan, Screenshot, State- und Log-Lesen bleiben getrennte Scripts.
- **Kein Composer:** Ein Script, das mehrere Live-Aktionen plant oder ausführt, ist kein Live-Spieler-Script und darf nicht als Playthrough-Erfolg archiviert werden.

### Schritt 4: Testen (30-120 Sekunden)
```
runtime_e2e_run → scenario_id: "freeze_step" oder "analyze_and_goal"
runtime_goal_play → goal: "GameState.run_id() != &''"
```
**Verdict:** PASS oder FAIL + Anomalien

### Schritt 5: Archivieren (5 Sekunden)
```json
{
  "name": "camera_move_to",
  "category": "runtime",
  "verdict": "PASS",
  "session": "2026-08-24",
  "path": "user://mcp_playthrough/scripts/camera_move_to.gd",
  "tested_with": ["freeze_step"],
  "description": "Kamera per Tween zu x,y bewegen"
}
```

### Schritt 6: Übergabe (automatisch)
Der nächste Agent beginnt bei Schritt 1 und liest den neuen Eintrag.

---

## Kategorien

| Kategorie | Inhalt | Beispiele |
|-----------|--------|-----------|
| `runtime` | Grundwerkzeuge | camera_move_to, freeze_step |
| `gameplay` | Spiel-Abfragen | faction_query_recursive, ship_list |
| `e2e` | Test-Logik | goal_play_enhanced, scenario_runner |
| `ux` | UI-Interaktion | scan_controls, find_button |
| `fix` | Bugfixes | faction_query_fix, camera_fix |

---

## Script-Format

Jedes Script in `user://mcp_playthrough/scripts/` muss:
1. `extends RefCounted` sein
2. `static func get_tool_defs() -> Array` liefern
3. `func dispatch_tool(tool_name, args) -> Variant` implementieren
4. Optional: `func dispatch_async(tool_name, args) -> Variant` für async Tools

---

## Archiv-Struktur

```
user://mcp_playthrough/
├── playthrough.jsonl          # Aktionen (existiert)
├── frames/                    # Screenshots (existiert)
├── snapshots/                 # GameState-Presets (existiert)
├── scripts/                   # NEU: Agent-Script-Archive
│   ├── index.jsonl            # Kategorie, Name, Zustand pro Script
│   ├── camera_move_to.gd      # Funktionierendes Modul
│   ├── faction_query_fix.gd   # Bugfix-Modul
│   └── goal_play_enhanced.gd  # Verbesserter Goal-Player
```

---

## Metriken

| Metrik | Bedeutung |
|--------|-----------|
| `index.jsonl` Einträge | Gesamtzahl archivierter Scripts |
| Scripts pro Kategorie | Verteilung der Lösungen |
| Durchschnittliche Test-Dauer | Geschwindigkeit pro Session |
| Agent-Skript-Verwendungsrate | Wie oft vorhandene Scripts genutzt werden |

---

## Fehlerbehandlung

| Situation | Aktion |
|-----------|--------|
| Script existiert bereits mit gleichem Namen | Neue Version als `<name>_v2.gd` oder UPDATE in index.jsonl |
| Test schlägt fehl | Script nicht archivieren, Fehler in index.jsonl dokumentieren |
| Archiv korrupt | JSONL ist append-only; letzte Zeile kann ignoriert werden |
| Kein MapCamera vorhanden | `runtime_camera_move_to` gibt `{"error": "MapCamera not found"}` zurück |

---

## Beispiel-Session

```
Agent 1 (Session 2026-08-24):
  1. Liest index.jsonl → 0 Einträge
  2. Analysiert Projekt → findet: camera_move_to fehlt
  3. Schreibt camera_move_to.gd
  4. Testet mit freeze_step → PASS
  5. Archiviert: index.jsonl + scripts/camera_move_to.gd

Agent 2 (Session 2026-08-25):
  1. Liest index.jsonl → 1 Eintrag: camera_move_to (PASS)
  2. Nutzt camera_move_to direkt → spart 10 Minuten Analyse
  3. Findet: faction_query braucht Fix
  4. Schreibt faction_query_fix.gd
  5. Testet mit new_game_to_world → PASS
  6. Archiviert: index.jsonl + scripts/faction_query_fix.gd

Agent 3 (Session 2026-08-26):
  1. Liest index.jsonl → 2 Einträge: camera_move_to + faction_query_fix
  2. Nutzt beide direkt → spart 20 Minuten Analyse
  3. Findet: goal_play braucht Retry-Logik
  4. Schreibt goal_play_enhanced.gd
  5. Testet mit analyze_and_goal → PASS
  6. Archiviert: index.jsonl + scripts/goal_play_enhanced.gd
```

---

## 🔁 Der vollautonome 8-Schritte Repair- & Feature-Loop (`agent_repair_loop.js`)

> **Eine Sprache:** Der gesamte Client-Stack ist Node/JS (`mcp_lib.js` + Playthrough-Helfer).
> Die früheren Python-Clients (`agent_repair_loop.py`, `mcp_client.py`, `remote_playout.py`,
> `vision_worker.py`, …) wurden entfernt — kein zweiter Protokoll-Client mehr.

Für geschlossene, vollautomatische Reparatur- und Feature-Entwicklungsläufe:

```
[1. Handshake]        initialize → protocol negotiated
       ↓
[2. Baseline]         godot://gameState/summary & godot://scene/current
       ↓
[3. Sandbox Start]    runtime_autonomy_workspace_begin
       ↓
[4. Edit & Patch]     runtime_autonomy_workspace_import + runtime_autonomy_patch
       ↓
[5. Gated Export]     runtime_autonomy_export (apply=true) + resource_barrier Settle
       ↓
[6. Headless Chain]   runtime_chain_run (Preflight / Contract Assertions)
       ↓
[7. Visible Verification] einzelne MCP-Atome, jeweils nach Live-Beobachtung entschieden
       ↓
[8. Verdict & Close]  PASS: sichtbare Evidenz + getrennte Game-/MCP-Findings
                      FAIL: runtime_autonomy_rollback_all nur für Workspace-Mutationen, nie als Gameplay-Ersatz
```

Ausführung via CLI:
```bash
node addons/mcp/client/agent_repair_loop.js \
  --file "res://scripts/..." \
  --old "old_code" \
  --new "new_code" \
  --goal "Feature oder Bugfix Beschreibung"
# optional: --chain chain.json (runtime_chain_run-Schritte) und
#           --sequence sequence.json (runtime_goal_sequence-Aktionen)
```

Der Repair-Loop ist ein Code-/Workspace-Modus. Sein optionales `goal_sequence` darf nicht für sichtbares Spieler-Playtesting verwendet werden; Live-Gameplay folgt ausschließlich `PLAYTEST_HANDOFF.md`.

**Evidence:** Jeder Workspace-Run erzeugt automatisch einen einheitlichen
Run-Trace (`user://mcp_traces/<run_id>.json`, Abruf über `runtime_run_trace
status|snapshot|list|read`) — Tool-Calls, GameState-Fingerprints, Events und
Verdict an EINER Trace-ID.

## 🗂 Versionierte Chain-Manifeste (`res://addons/mcp/mcp_chains/`)

Wiederholbare Testketten als JSON (F5). Katalog ansehen, laden, ausführen:
```bash
# Katalog + Validierung + Lauf (Profile qa|dev, sichtbares Spiel):
runtime_chain_list
runtime_chain_load  {"chain_id": "world_smoke"}
runtime_chain_run   {"chain_id": "preflight_core"}   # headless Preflight-Kern
runtime_chain_run   {"chain_id": "world_smoke"}      # visible Smoke am laufenden Spiel
```
Manifeste sind versioniert (git) und werden vor Ausführung validiert
(`runtime_chain_validate`); Assertions binden das Tool-Result als `result`
und dürfen zusätzlich GameState lesen (`has_active_run()` etc.).
