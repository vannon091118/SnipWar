# AGENTS.md — GDScript MCP Bridge (Pflicht-Lektüre für MCP-Tests)

> **Dieses Dokument ist die Pflicht-Lese-Instruktion für ALLE MCP-Test-Arbeit.**
> Es lebt IM MCP-Addon und ist strikt getrennt vom Projekt-`AGENTS.md` (SnipWar):
> Hier steht die MCP-Test-Doktrin, dort das Spiel. Beide verweisen aufeinander,
> mischen sich aber nicht.
>
> **Regel:** Vor jedem MCP-Test-Lauf liest der Agent dieses Dokument + die unten
> verlinkten Pflicht-Dokumente. Die Projekt-AGENTS.md gilt für Spiel-Logik,
> Preflight, DOKI — NICHT für MCP-Test-Details (die stehen hier).

---

## 📋 PFLICHT-LESEDOKUMENTE (in dieser Reihenfolge)

| # | Dokument | Warum Pflicht |
|---|----------|---------------|
| 1 | **`AGENTS.md` (diese Datei)** | MCP-Test-Doktrin: Transport, OCR-Pflicht, Entkopplung, Atom-Vertrag |
| 2 | **`MCP_INDEX.md`** | Architektur, Tool-Liste (alle 107+ Tools), Schnellstart, Fallstricke |
| 3 | **`AGENT_WORKFLOW.md`** | Autonome Playtesting-Umgebung, Modi strikt trennen (Live/Repair/Vertrag/Editor) |
| 4 | **`PLAYTEST_HANDOFF.md`** | Session-Profile (player/qa/dev) + verbindlicher Spieler-Vertrag + Atom-Registry |
| 5 | **`MCP_ANOMALIES.md`** | GAME vs MCP-Mismatch-Referenz — trennt Spiel-Bugs von Tool-API-Problemen |
| 6 | **`client/playthroughs/MCP_PLAYTEST_REPORT.md`** | Live-Playthrough-Archiv (was sichtbar verifiziert wurde) |
| 7 | **`PERSISTENCE.md`** | Persistenz-Landkarte: was wohin persistiert, TTLs, Retention, Versionierung, Backup |

**Projekt-Doku (nicht hier):** `DESIGN.md`, `VISION.md`, `docs/FINDINGS.md`,
`docs/mcp_live_test_results.md` — Spiel-Findings und Session-Hergang. Die
**zentrale FINDINGS-Datei** (`docs/FINDINGS.md`) ist die Todo-Referenz für
Befunde; MCP-Befunde werden dort unter „MCP-Findings" geführt, Spiel-Befunde
unter „Spielfindings" — getrennt, wie hier.

---

## 🚀 MCP-Test-Doktrin (verbindlich)

### 1. Standard-Transport: `mcp_file_driver.js`
- Eine Befehlszeile = **genau ein Tool-Call**; ein Prozess + ein Handshake pro Lauf.
- Latenz ~4–16 ms. Kein FIFO-/Session-Basteln, keine `atomic_session`-Skripte.
- Nutzung: `MCP_COMMANDS=<file> MCP_OUTPUT=<file> node addons/gdscript_mcp/client/playthroughs/atomic/mcp_file_driver.js`
- Port: Editor-Server = **9091**, Runtime (Spiel) = **9090** — nicht verwechseln.

### 2. Nie bei unerwarteten Ergebnissen raten
Der Server hängt bei unerwarteten Lagen **automatisch** `visual_evidence` an:
- Fehler (`ok:false`, `_error`, „Node not found"), `clicked:false`, `moved:false`,
  leere Scans (`controls:[]`).
- Die Analyse (Screenshot + OCR) ist **entkoppelt**: Die Aktion antwortet sofort
  (`visual_evidence: {status: "pending"}`), die Analyse läuft im Hintergrund in
  einen Cache. Abruf: **`runtime_visual_evidence`** (`wait_ms` pollt, `capture`
  startet frisch) → `{status: none|pending|ready, evidence: {screenshot, ocr}}`.
- **Workflow:** Antwort bewerten → bei Bedarf `runtime_visual_evidence` abrufen
  (meist schon `ready`). Nie blind weitermachen.

### 3. OCR-Pipeline
- Tesseract.js im Client-Ordner (`npm install tesseract.js`), Assets lokal
  (Kaltstart ~2,3 s), Worker-Pool default 2 (`MCP_OCR_POOL`).
- `ocr.available: true` + `text` + `confidence` — bei `available:false` den
  `reason` lesen (nicht raten).

### 4. Atom-Vertrag für sichtbare Spieler-Läufe
- Sichtbares Gameplay = einzelne MCP-Atome (ein Tool-Call pro Schritt): Scan →
  Maus-Move → optional Scan → Klick/Scroll → separater Wait/Scan.
- Keine GameState-Mutation, kein `runtime_goal_sequence/play/chain_run` für
  sichtbare Spielerläufe (Details: `PLAYTEST_HANDOFF.md`).

### 5. Maus-Automatik (nie springen)
- `runtime_click` approachiert selbst weich (`smooth_travel`, min 8 Steps,
  distanzbasiert bis 31+ Steps). Kein separates `mouse_move` nötig; der Cursor
  springt grundsätzlich nie.

### 6. Editor-Modus
- Editor-Server = 9091, Runtime = 9090 (`editor_run_project with_mcp=true`).
- **OFFEN-1 gelöst:** `play_main_scene` startet das Spiel als separaten Prozess;
  das Plugin setzt `MCP_EMBEDDED=1` (+ Port/Profil/Writes-Env) und der
  `McpRuntime`-Autoload bootet den Server im Spiel-SceneTree des Kind-Prozesses.
  Der Dock verbindet sich selbsttätig auf 9090, sobald das Spiel läuft.

### 7. Externe MCP-Clients (stdio_bridge) — absolute Pfade Pflicht
- Externe Clients (z. B. Freebuff „choose tools“) starten
  `python addons/gdscript_mcp/client/mcp_stdio_bridge.py` oft mit **ihrem eigenen
  cwd** (z. B. `%USERPROFILE%`) — relative Pfade lösen dann gegen
  `C:\Users\<User>\addons\...` auf → `MODULE_NOT_FOUND`, der Server startet
  nie (Befund MCP-08 in `docs/FINDINGS.md`).
- **Regel:** In Client-Konfigurationen IMMER den cwd-immunen Wrapper mit
  **absolutem** Pfad eintragen:
  `C:\Users\Vannon\Documents\snippet-empire\snip-war\mcp_bridge.cmd`
  (Wrapper leitet den Bridge-Pfad über `%~dp0` ab — immer Projektroot, cwd
  des Clients egal).
- Der Bridge ist zero-dependency (Python stdlib: `socket`/`select`), verbindet
  TCP `127.0.0.1:9090` (Runtime; Editor-Kontext: 9091) und nutzt kein
  `os.getcwd()` — nur der Startpfad selbst ist die Falle.
  Legacy: `mcp_stdio_bridge_legacy.js` (Node.js), archiviert.

---

## 🔄 MCP-Test-Workflow (Kurzfassung)

1. **Vor jedem Lauf:** Diese Datei + Pflicht-Doku 1–6 lesen.
2. **Spiel starten:** `$GODOT_BIN --path . -- --mcp --mcp-port 9090` (sichtbar,
   kein Headless — der Server verweigert Headless).
3. **Driver:** `mcp_file_driver.js` auf Port 9090 (Runtime) starten.
4. **Aktionen:** Scan → Move → Klick atomar; bei Abweichung `runtime_visual_evidence`.
5. **Befunde:** In `docs/FINDINGS.md` nachtragen (Status ✅/🟡/🔵 + Beleg) —
   MCP-Findings getrennt von Spiel-Findings. Mitcommitten.

---

## 📁 Doku-Landkarte (was wo lebt)

| Thema | Datei |
|-------|-------|
| MCP-Test-Doktrin (diese Datei) | `addons/gdscript_mcp/AGENTS.md` |
| MCP-Architektur & Tools | `addons/gdscript_mcp/MCP_INDEX.md` |
| MCP-Workflow & Modi | `addons/gdscript_mcp/AGENT_WORKFLOW.md` |
| MCP-Spieler-Vertrag | `addons/gdscript_mcp/PLAYTEST_HANDOFF.md` |
| MCP-Anomalien (GAME vs MCP) | `addons/gdscript_mcp/MCP_ANOMALIES.md` |
| MCP-Persistenz (Landkarte, TTLs, Backup) | `addons/gdscript_mcp/PERSISTENCE.md` |
| Live-Playthrough-Archiv | `addons/gdscript_mcp/client/playthroughs/MCP_PLAYTEST_REPORT.md` |
| Zentrale Findings (Spiel + MCP, getrennt) | `docs/FINDINGS.md` |
| Spiel-Doku | `DESIGN.md`, `VISION.md` |
| Projekt-Instruktion (Spiel, Preflight, DOKI) | `AGENTS.md` (Projekt-Wurzel) |
