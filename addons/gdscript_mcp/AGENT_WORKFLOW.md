# MCP Agent Workflow — Autonome Playtesting-Umgebung

**Stand:** 2026-08-24
**Ziel:** Unkomplizierte, umfassende Autonomie für Agents, die mit jeder Benutzung schneller und präziser wird.

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
runtime_analyze_project   → Szenen, Autoloads, GameState-API
runtime_analyze_input     → _input/_unhandled_input Treffer
runtime_analyze_game_state → Öffentliche GameState-Methoden
```
**Frage:** "Welche Lücken gibt es die mein Archiv nicht abdeckt?"

### Schritt 3: Scripts schreiben oder fixen (variabel)
- **Neues Script:** In `user://mcp_playthrough/scripts/<name>.gd` schreiben
- **Bestehendes Script fixen:** Kopie anlegen, fixen, altes Archivieren
- **Atomar:** Jedes Script ist ein eigenständiges Modul mit `get_tool_defs()` + `dispatch_tool()`

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
