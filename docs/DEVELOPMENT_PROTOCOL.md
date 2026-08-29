# SnipWar — Entwicklungsprotokoll

**Zweck:** Reproduzierbarer Arbeitsablauf für Phase 1 auf jedem zweiten Entwicklungsrechner.

## 1. Voraussetzungen

- Git mit Zugriff auf `origin/main`
- Godot `4.7.2-stable` als Console-Binary
- Python `>=3.11` für `narrative_runtime`
- Node.js nur für MCP-/E2E-Werkzeuge, sofern diese Phase sie benötigt
- vollständiges PC-Profil nach [`PC_DEVELOPMENT_PROFILE.md`](PC_DEVELOPMENT_PROFILE.md)
- identischer Repository-Checkout; keine lokalen Änderungen vor dem Pull verwerfen

## 2. Erstes Einrichten auf dem zweiten System

```bash
git clone https://github.com/vannon091118/SnipWar.git
cd SnipWar
git switch main
git pull --ff-only origin main
export GODOT_BIN="/absolute/path/to/Godot_v4.7.2-stable_console"
```

Unter Windows Git Bash:

```bash
export GODOT_BIN="C:/Pfad/zu/Godot_v4.7.2-stable_win64_console.exe"
```

Danach einmal den Godot-Klassenscan ausführen:

```bash
"$GODOT_BIN" --headless --path . --editor --quit
```

`.uid`-Dateien gehören zum Repository und dürfen nicht gelöscht werden.

## 3. PC-Gesundheit vor Entwicklungsbeginn

Vor einem Rechnerwechsel oder einer längeren Testphase das [PC-Entwicklungsprofil](PC_DEVELOPMENT_PROFILE.md) ausfüllen. Hardwarewerte werden gemessen, nicht geschätzt. RAM-Takt, CPU/GPU-Temperaturen, SMART/NVMe-Zustand, I/O-Fehler, Stromversorgung und Stabilitätstests sind eigene Nachweise und werden nicht durch einen bestandenen Godot-Test ersetzt.

## 4. Arbeitsbeginn

```bash
git status --short --branch
git pull --ff-only origin main
```

Vor Änderungen lesen:

- `AGENTS.md`
- `PLAN.md`
- `docs/CODEBASE_AUDIT.md`
- `docs/FINDINGS.md`
- `scripts/doki/README.md`
- bei MCP-Arbeit zusätzlich `addons/gdscript_mcp/AGENTS.md`

Keine lokalen Änderungen anderer Arbeitsstände überschreiben, stashen oder zurücksetzen.

## 5. Architekturverträge

- `GameState` ist die einzige autoritative Live-Spielwelt.
- `WorldState` ist nur temporärer Vorgeschichts-Simulationszustand.
- `EventBus` ist die Grenze zwischen Gameplay und Chronik.
- `HistoryEvent` bleibt sprachneutral; Locale-Templates sind reine Projektion.
- Snapshots und Renderer dürfen nicht direkt auf Simulatorinternals oder `GameState` zugreifen.
- DOKI bleibt reines Commit-Gate und wird nicht mit der Spielhistorie gekoppelt.
- Slot 0 ist ein echter Spielstand und darf für Tests nie gelöscht oder überschrieben werden.

## 6. Verifikation vor Commit

```bash
"$GODOT_BIN" --headless --path . --script res://scripts/testing/compile_gate.gd
"$GODOT_BIN" --headless --path . --script res://scripts/testing/chronicle_core_test.gd
"$GODOT_BIN" --headless --path . --script res://scripts/testing/chronicle_lifecycle_test.gd
"$GODOT_BIN" --headless --path . --script res://scripts/testing/historical_playback_test.gd
"$GODOT_BIN" --headless --path . --script res://scripts/preflight.gd -x
```

Erwartung: `RESULT: PASSED`. Headless-RID-Leaks und Reload-Rauschen sind nur dann akzeptabel, wenn der Prozess mit Erfolg beendet und die Assertions bestanden sind.

## 7. DOKI-Commitablauf

Direkte Commits ohne DOKI sind verboten:

```bash
git add <gezielte-dateien>
"$GODOT_BIN" --headless --path . --script res://scripts/doki/doki.gd -- prepare "<präziser Impuls>"
# Narrator-Body nach .doki/prompt.txt schreiben
"$GODOT_BIN" --headless --path . --script res://scripts/doki/doki.gd -- finish --body-file .doki/narrator_body.md
git commit -F .commit_msg.txt
```

Bei einem abgebrochenen Flow:

```bash
"$GODOT_BIN" --headless --path . --script res://scripts/doki/doki.gd -- repair
```

DOKI-Artefakte (`narrative_chain.json`, `change_index.json`, `CHANGELOG.md`, `scripts/doki/data/arcs.json`) werden vom Flow verwaltet. Sie nicht manuell rekonstruieren.

## 8. Sicheres Synchronisieren zwischen Systemen

```bash
git status --short --branch
git pull --ff-only origin main
```

Wenn der Push vom ersten System erledigt wurde, reicht auf dem zweiten System ein Fast-Forward-Pull. Wenn auf beiden Systemen gearbeitet wurde, zuerst einen Topic-Branch verwenden und niemals ungeprüft forcieren:

```bash
git switch -c phase-1/<kurzer-name>
```

Vor dem Wechsel zwischen Systemen müssen Änderungen entweder committed und gepusht oder bewusst lokal dokumentiert sein. Uncommitted DOKI-Sessions nicht auf das zweite System übertragen; dort `doki repair` ausführen.

## 9. Phase-1-Arbeitsprotokoll

Jede Arbeitseinheit dokumentiert:

- Ziel und betroffene atomare Commit-Gruppe
- Ausgangs- und End-Commit
- geänderte Dateien
- Tests und exakte Ergebnisse
- bekannte Warnungen
- offene Risiken oder Folgeentscheidungen

Das Protokoll gehört in den Commit-Body bzw. in die passende Dokumentation; es ersetzt keine Tests und keine Findings.

## 10. Fehlerregel

Ein Parserfehler, ein fehlgeschlagener Preflight oder ein verletzter Architekturvertrag stoppt die Arbeitseinheit. Erst Root Cause beheben, dann erneut vollständig verifizieren. Keine Skips, Workarounds oder erwarteten Fehler als Erfolg behandeln.
