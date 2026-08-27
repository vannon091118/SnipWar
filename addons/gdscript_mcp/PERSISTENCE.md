# MCP Persistenz — Verbindliche Landkarte

> **Diese Datei ist die autoritative Referenz dafür, was im MCP wohin persistiert,
> wie lange es lebt und was versioniert (git) vs. ephemer (`user://`) ist.**
> Jede neue MCP-Datenablage MUSS hier ergänzt werden, bevor sie committet wird.
> Pflicht-Lese vor jeder MCP-Arbeit (siehe `AGENTS.md`).

## Grundprinzipien

1. **Drei Speicherwelten, strikt getrennt:**
   | Welt | Pfad | Versioniert? | Lebensdauer |
   |---|---|---|---|
   | **Projekt (git)** | `res://` | ✅ committet | dauerhaft, mit dem Repo |
   | **Nutzerdaten (App-user)** | `user://` | ❌ nie committen | persistent über Neustarts, lokal pro Rechner |
   | **Cache (gitignored)** | `node_modules/`, `user://`-Cache | ❌ | regenerierbar |

2. **`user://` überlebt Neustarts** — es ist der einzige Ort für Runtime-Zustand,
   der zwischen Sessions erhalten bleiben muss (Workspaces, Traces, Playthrough-
   Archiv, Profile). `res://` ist für **versionierte, wiederverwendbare** Inhalte
   (Chain-Manifeste, Client-Registrierung).

3. **Ephemer ist explizit:** Kontext-Artefakte (Screenshots) sind **bewusst**
   kurzlebig (TTL 45 s) — sie sind Evidenz-Cache, kein Archiv. Dauerhafte
   Evidenz gehört in den Run-Trace (`user://mcp_traces`).

---

## Vollständige Ablage-Landkarte

### A. Projekt (res://, versioniert — git)

| Pfad | Inhalt | Garantie |
|---|---|---|
| `.mcp.json` | MCP-Client-Registrierung (stdio-Bridge → 9090) | wird mitcommittet; jeder Client kann das Spiel über `.mcp.json` registrieren |
| `res://mcp_chains/*.json` | Versionierte Chain-Manifeste (F5) | PASS ist nur echt, wenn die Kette so lief; Manifeste sind wiederholbar und diffbar |
| `res://addons/gdscript_mcp/` | Addon-Code + Doku | komplett versioniert (inkl. `.gd.uid`-Sidecars) |
| `res://addons/gdscript_mcp/client/node_modules/` | tesseract.js + OCR-Assets-Cache | ❌ gitignored — regenerierbar via `npm install`; `deu.traineddata` liegt im lokalen Cache |

### B. Nutzerdaten (user://, persistent — nie committen)

| Pfad | Inhalt | TTL / Retention | Cleanup |
|---|---|---|---|
| `user://mcp_traces/<run_id>.json` | **Run-Trace (F4)**: Tool-Calls, Fingerprints, Events, Verdict | **Retention-Policy:** `runtime_run_trace action=prune max_days=N` (Default 30) — Traces älter als N Tage werden gelöscht | manuell/Agent via prune; Abruf `list`/`read` |
| `user://mcp_workspaces/run_*/` | Journaled Autonomy-Workspace: `manifest.json`, `preimages/`, Dateien | persistiert bis explizites `workspace_end`/Rollback | `runtime_autonomy_workspace_end` finalisiert; `rollback_all` räumt Mutationen |
| `user://mcp_playthrough/` | Playthrough-Archiv: `playthrough.jsonl`, `frames/*.png`, `snapshots/*.tres`, `scripts/index.jsonl` | persistiert; akkumuliert | keine automatische Löschung (Archiv) |
| `user://mcp_context/<role>_<session>/` | Screenshot-Artefakte + Metadaten | **TTL 45 s** (Default), max 6 Records, max 32 MB | `mcp_context_store.cleanup()` alle 2 s + Lifecycle-Tick; `runtime_context_release` einzeln |
| `user://gdscript_mcp_profile.cfg` | Play-Goal-Profil (player/qa/dev) aus dem Dock | persistent | — |
| `user://gdscript_mcp_config.cfg` | Editor-Server-Konfig (Port, Transport, Writes) | persistent | — |
| `user://mcp_preflight_result.json` | Preflight-Ergebnis für Chain-Subprozess-Poll | transient (wird nach Read gelöscht) | Chain-Controller entfernt die Datei nach dem Poll |
| `user://mcp_test_config.cfg` | Test-Szenario-Schalter | persistent | — |

### C. Cache (gitignored, regenerierbar)

| Pfad | Inhalt | Regenerierung |
|---|---|---|
| `addons/gdscript_mcp/client/node_modules/.cache/tesseract.js/` | `deu.traineddata.gz` + Worker-Assets | `npm install` + einmaliger Download (Offline-Kaltstart 2,3 s) |

---

## 2. Garantien (verbindlich)

1. **Run-Traces überleben Server-/Spiel-Neustarts** — Export ist ein synchroner
   Datei-Write nach `user://mcp_traces/` beim `end` (Workspace-Ende oder manuell).
   Ein abgebrochener Prozess verliert höchstens den noch nicht exportierten
   In-Memory-Trace; die letzte Werkstatt-/Preflight-Phase wird vor dem Verdict
   exportiert.
2. **Workspace-Rollback ist persistent:** Preimages + `manifest.json` liegen auf
   Disk; `runtime_autonomy_rollback`/`rollback_all` stellen auch nach einem
   Prozess-Neustart den Baseline-Zustand wieder her (Hash-basiert).
3. **Chain-Manifeste sind diffbar & wiederholbar:** in git; `runtime_chain_load`
   validiert vor jedem Lauf; ein „PASS“ referenziert `manifest_path` + `chain_id`
   im Trace.
4. **Profile/Config überleben Neustarts** (`user://gdscript_mcp_profile.cfg`,
   `user://gdscript_mcp_config.cfg`) — der Dock liest sie beim Boot.
5. **Evidenz vs. Cache:** Screenshot-Artefakte sind kurzlebig (TTL 45 s);
   dauerhafte Evidenz ist der Run-Trace (der `context_id`s referenziert, aber
   nicht von deren Existenz abhängt).
6. **`user://` wird nie committet** — das `.gitignore` deckt `node_modules/`,
   `.doki/`, `.commit_msg.txt` ab; `user://` ist außerhalb des Repos (Godot
   `app_userdata`).

## 3. Backup & Aufräumen

- **Backup:** `user://mcp_traces/` + `user://mcp_playthrough/` + `user://mcp_workspaces/`
  sind die wertvollen Artefakte. Ein Backup-Kopier dieser drei Ordner sichert die
  komplette MCP-Evidenz-Historie.
- **Aufräumen Traces:** `runtime_run_trace {"action":"prune","max_days":30}` —
  löscht Traces älter als N Tage (Default 30). Ohne prune akkumulieren Traces
  (bewusst: Evidenz-Historie).
- **Aufräumen Workspaces:** `runtime_autonomy_workspace_end` nach jedem Run;
  abgebrochene Workspaces (Crash) können manuell unter `user://mcp_workspaces/`
  gelöscht werden — die Baseline-Verifikation meldet den Zustand.
- **Aufräumen Kontext:** automatisch (TTL 45 s, 6 Records, 32 MB) — kein
  manueller Eingriff nötig.

## 4. Konsistenz-Regeln (wenn du etwas Neues persistierst)

1. Neue `user://`-Ablage → hier eintragen (Pfad, Inhalt, TTL/Retention, Cleanup).
2. Neue `res://`-Ablage → versioniert committen (inkl. `.uid`-Sidecar falls `.gd`).
3. Kein `user://`-Pfad darf in `res://`-Logik hart verdrahtet werden ohne Eintrag
   in dieser Datei.
4. Retention: Jede persistente Ablage braucht eine dokumentierte Lebensdauer —
   entweder TTL, explizite Löschung oder „Archiv (akkumuliert)“.
5. Die Tool-Liste in `MCP_INDEX.md` und die Pflicht-Lese in `AGENTS.md` nennen
   diese Datei als Referenz.

## 5. Tool-Zugriff auf Persistenz

| Tool | Persistenz-Bezug |
|---|---|
| `runtime_run_trace` (status/begin/end/snapshot/list/read/prune) | Run-Traces lesen, exportieren, prunen |
| `runtime_autonomy_workspace_status` / `_end` / `rollback_all` | Workspace-Lebenszyklus |
| `runtime_playthrough_search` / `latest` / `stats` / `frames` | Playthrough-Archiv lesen |
| `runtime_context_list` / `_release` / `_cleanup` | Kontext-Artefakte verwalten |
| `runtime_chain_list` / `_load` | Chain-Manifest-Katalog |