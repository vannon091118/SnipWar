# SnipWar & MCP Autonomie — Masterplan & Roadmap

**Stand:** August 2026
**Doktrin:** Code schlägt Dokument. Dieses Dokument ist der verbindliche Masterplan für das Gesamtsystem und das autonome MCP-Subprojekt (`addons/gdscript_mcp`). Der portable Arbeitsablauf für Phase 1 ist in [`docs/DEVELOPMENT_PROTOCOL.md`](docs/DEVELOPMENT_PROTOCOL.md) festgehalten.

---

## 1. Übersicht & Systemarchitektur

SnipWar besteht aus zwei eng verzahnten, aber architektonisch sauber getrennten Systemen:
1. **SnipWar Core Game**: Strategischer 3-Layer-Overworld-Simulator in Godot 4.7 (SSO: `GameState`, 4 Domänen: Faction, Economy, Tech, Ship; Headless-Preflight-Suite mit 43 deterministischen Constraints).
2. **MCP Autonomy Bridge (`addons/gdscript_mcp`)**: Eigenständiges Subprojekt im Projekt. Eine JSON-RPC 2.0 Brücke (TCP 9090 / stdio) für externe KI-Agenten und Testframeworks mit eigenem Server-Lifecycle (`PROCESS_MODE_ALWAYS`), deterministischer Maus-/Frame-Steuerung, UX-Pipeline, OCR/Vision-Artefakten und journalisierter Sandbox-Autonomie.

---

## 2. Zielbild: Der geschlossene autonome Entwicklungs- & Test-Loop

Das Zielbild ist ein Agent, der ohne menschliche Interaktion neue Features bauen, Bugs reproduzieren, beheben und verifizieren kann:

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. User-Goal & Impact-Analyse                                            │
│    • Code- & Signal-Analyse, ConceptIndex, Dependency Graph              │
│    • Identifikation der betroffenen atomaren Commit-Gruppe               │
└────────────────────────────────────┬────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 2. Isolierte Workspace-Transaktion (user://mcp_workspaces/run_*)        │
│    • Baseline-Fingerprint & Hash-Erfassung                              │
│    • Journaled Write / Single-Occurrence Patch                           │
│    • Lokale GDScript-Syntax- und Parse-Diagnostik                       │
└────────────────────────────────────┬────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 3. Gated Export & Headless-Validierung                                  │
│    • Fail-closed Export nach res:// bei validem Hash & Syntax            │
│    • Preflight-Constraints & modulare Test-Suites (Headless)            │
└────────────────────────────────────┬────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 4. Sichtbare Runtime- & Gameplay-Validierung (Visible Renderer)          │
│    • Liveness-Receipt (Helper & Game ready)                             │
│    • Deterministische Interaktion (Kamera, UX-Click, Key-Events)         │
│    • Freeze / Step-Frame zur exakten Zustandsprüfung & Reproduktion      │
│    • SceneTree- & Live-Control-Snapshots + Bild-/OCR-Evidenz            │
└────────────────────────────────────┬────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 5. Unified Evidence Trace & Archivierung                                │
│    • Zusammenführung: Diff + Input-Event + State + Bild + Logs          │
│    • Erfolgreiche Skripte & Snapshots in user://mcp_playthrough/        │
│    • Atomarer Git-Commit nach AGENTS.md Konvention                      │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Umsetzungsstatus der MCP-Autonomie-Phasen

| Phase | Bereich | Status | Details |
|---|---|---|---|
| **Phase 1** | Autonomy Contracts & Discovery | ✅ **Fertiggestellt** | `McpAutonomyContracts`, Capability-Metadata, normalized Receipts, read-only Probes. |
| **Phase 2** | Edit Workspace & Journaling | ✅ **Fertiggestellt** | `McpWorkspaceJournal`, `McpProjectTools`, Sandbox `user://mcp_workspaces/run_*`, Preimage-Hashing, Single-Occurrence-Patching, Gated Export, Rollback, strukturierte Syntax-Diagnostik & `resource_barrier`. |
| **Phase 3** | Declarative Chain Controller | ✅ **Fertiggestellt** | `McpChainController`: Verbindet Headless Preflight mit sichtbaren E2E-Szenarien in deklarativer Kette (`runtime_chain_run`, `runtime_chain_trace`). |
| **Phase 4** | Autonomous Goal & Repair Loop | ✅ **Fertiggestellt** | `McpGoalPlayer`: Deterministisches Feature-Testing (`runtime_goal_sequence`), `agent_repair_loop.js` (geschlossener Self-Healing-Loop, JS-Client). |
| **Phase 5** | Unified Evidence & MCP Resources | ✅ **Fertiggestellt** | MCP Resources (`godot://scene/current`, `godot://logs/recent`, `godot://gameState/summary`, `godot://test/results`), Push-Notifications (`list_changed`) und standardisierter Evidence-Trace. |

---

## 4. MCP-Mismatches & Tooling-Fixes (M1–M6)

| ID | Problem | Lösung | Status |
|---|---|---|---|
| **M1** | `runtime_ux_analyze` Response > 100KB bricht JSON-Parser | Größenbudgets (`max_controls`), Truncation-Marker, Paginierung. | ✅ |
| **M2** | `game_faction_query` liefert leeres Array bei verschachtelten Nodes | Rekursive Suche in `PlanetField`-Containern. | ✅ |
| **M3** | `runtime_click` scheitert bei Area2D/Node2D-Planeten | Viewport-Koordinatentransformation via `MapCamera`. | ✅ |
| **M4** | `runtime_eval` erfordert Dev-Flag | GoalPlayer nutzt isolierte Expression-Evaluierung; `--mcp-developer` für Runtime-Eval. | ✅ |
| **M5** | TCP Reconnect nach Server-Neustart | Client-seitiger Reconnect-Loop & Liveness-Polling. | ✅ |
| **M6** | Fehlende direkte Kamera-Navigation (12+ Drags nötig) | `runtime_camera_move_to(x, y, zoom, duration)` mit Easing. | ✅ |

---

## 5. Gameplay- & Feature-Roadmap (SnipWar Core)

1. **Forschungs-Progression (S1)**: Zeitgesteuerte Technologien mit `research_time > 0` und visuellem Countdown-Indikator über Planeten.
2. **Steuerung & Onboarding (S2)**: `InputHintOverlay` für WASD-, Zoom- und Aktions-Hotkeys.
3. **Scout & Expansion (S3)**: Kostenloser Start-Scout mit Drag-and-Drop Erkundungs-Dispatch.
4. **Kamera-Zentrierung (S4)**: Deterministischer Start-Fokus auf die Homeworld mit Nachbarschafts-FoV.
5. **UI-Layout-Zonen (S6)**: Nicht-überlappende `ControlField`-Zonen (Dossier links, Flotte/Wirtschaft rechts, VaultBar oben).
6. **Autonome Feature-Verifikation**: Jedes neue Gameplay-Feature wird durch ein zugehöriges MCP-E2E-Szenario automatisiert im sichtbaren Lauf verifiziert.

---

## 6. Verbindliche Entwicklungs- & Commit-Regeln

- Alle Änderungen folgen den in [`AGENTS.md`](AGENTS.md) definierten **atomaren Commit-Gruppen**.
- Vor jedem Commit muss die Preflight-Suite (`scripts/preflight.gd -x`) fehlerfrei durchlaufen (`RESULT: PASSED`).
- `.uid`-Dateien (`*.gd.uid`) werden stets mitversioniert.
