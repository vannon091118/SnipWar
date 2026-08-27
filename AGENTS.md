# SnipWar Agent Notes

---

## 🚀 QUICK START — WAS JEDER AGENT SOFORT WISSEN MUSS

### 1. Godot Binary & Headless
```bash
export GODOT_BIN="C:/Users/Vannon/Desktop/godu/Godot_v4.7.2-stable_win64_console.exe"
# Alle Headless-Calls: $GODOT_BIN --headless --path . --script res://scripts/...
```

### 2. ZWEI SUCH-TOOLS (statt grep/rg)

| Frage | Tool | Beispiel |
|-------|------|----------|
| **Architektur**: Klassen, Domänen, freie Slots, Synonyme | `concept_search.gd` | `$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd fleet` |
| **Volltext**: String in .tres/.tscn/.md/.json + Kontext | `global_search.gd` | `$GODOT_BIN --headless --path . --script res://scripts/global_search.gd "fleet_supply_bonus" --type tres,json` |

**ConceptIndex CLI** (semantisch):
```bash
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd fleet          # Suche
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --unmapped      # Ungemappte Klassen
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --free-slots    # Freie Slots
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --class ShipManager
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --domain economy
```

**Global Search CLI** (SearchCore-Engine, LLM-JSON-Output, immer mit Abhängigkeiten):
```bash
# Output ist IMMER ein kompaktes JSON (kein --no-json nötig):
#   results[]            Treffer + Kontext
#   classes_available    {ClassName: res://Pfad} — wer ist verfügbar
#   dependency_graph     je Datei: class_name, extends, preloads[], loads[]
$GODOT_BIN --headless --path . --script res://scripts/global_search.gd "fleet"
$GODOT_BIN --headless --path . --script res://scripts/global_search.gd "assemble_ship" --type gd --context 5
$GODOT_BIN --headless --path . --script res://scripts/global_search.gd "runtime_audio|runtime_animation"  # OR-Suche
$GODOT_BIN --headless --path . --script res://scripts/global_search.gd "func (_?[a-z_]+)" --regex  # Capture-Groups
# 2 Tool-Calls füralles: Klassen + Abhängigkeiten + Verfügbarkeit in EINEM Output
```

### 3. Preflight (Verbindlicher Qualitäts-Check)
```bash
$GODOT_BIN --headless --path . --script res://scripts/preflight.gd -x   # Full Suite (38 Constraints, ~100s, V2 Architecture)
$GODOT_BIN --headless --path . --script res://scripts/preflight.gd --filter=concept_index -v  # Einzelne Constraint
```
**Verbindlich:** `RESULT: PASSED` — ERROR-Traces am Ende sind normales Headless-Rauschen.
**V2 Features:** Auto-Discovery, Phase-Split (Pure/Scene), Fail-Fast mit Summary, Isolation Warnings.
**Legacy V1:** `scripts/legacy/preflight_v1.gd` — archiviert, nicht aktiv.

### 4. Commit-Workflow (Hooks aktiv, DOKI CommitLayer als Tor!)
```bash
# JEDER Commit läuft durch den DOKI-Flow (sonst blockt pre-commit):
git add <datei1> <datei2> ...                 # NIEMALS git add -A / .
$GODOT_BIN --headless --path . --script res://scripts/doki/doki.gd -- prepare "<impuls>"
#   → liest .doki/prompt.txt: Narrator + Mood + Composite (deterministisch)
#   → Agent schreibt den Commit-Body in der Rolle des Narrators (Fließtext)
$GODOT_BIN --headless --path . --script res://scripts/doki/doki.gd -- finish --body-file .doki/narrator_body.md
#   → 9 Checks (1-6 weich, 7-9 HART), schreibt .commit_msg.txt + staged Doku-Artefakte
git commit -F .commit_msg.txt                  # Hook re-verifiziert + finalize/push automatisch

# Narrative-Qualitäts-Analyse (was DOKI geschrieben hat, logisch konsistent?):
$GODOT_BIN --headless --path . --script res://scripts/doki/doki_analyze.gd
#   → Narrator-Fussspur, Mood-Regel (nie zweimal gleich), Composite-Monotonie,
#     Kausalität (Vorgänger-Erwähnung), Arc-Verlauf, Beziehungs-Matrix,
#     CHANGELOG-Sync — Befunde: 0 Fehler / N Warnungen = Nachbesserungsstellen
# Repair nach rebase/amend/Crash:  doki repair
```
**Begründungszeilen** (`- pfad/datei: Grund.`) erzeugt **DOKI maschinell** im `finish` — nicht mehr manuell schreiben.
**Verbotene Direkt-Commits:** `git commit -m` ohne DOKI-Flow → pre-commit Hook blockt (Exit 1).
**pre-commit führt zusätzlich Preflight aus** → bei FAIL: fixen, neu stagen, commit wiederholen.

### 5. DOKI CommitLayer — So funktioniert das System
**Reines Commit-Gate:** DOKI ist eine eigenständige Komponente unter `scripts/doki/`.
Es hat **KEINEN Kontakt zu MCP, Nipper, Agent-Systemen oder Spiel-Logik** —
keine Imports, keine Autoloads, keine Signale. Einzige Schnittstellen: Git-Befehle
(`DOKI_GitHelper`) und eigene Dateien (`.doki/`, `narrative_chain.json`, `change_index.json`,
`CHANGELOG.md`, `.commit_msg.txt`, `.githooks/`).

**Schichten (inward-only):** `core` (Rng/Verifier) ← `chain` (Stores) ← `character` ← `prompt` ← `orchestration` (Flows)

**Determinismus:** Composite aus Djb2+XorShift128 (32-Bit-maskiert, 10×Warmup; kein SplitMix) (Seed = Chain + TreeHash + DiffHash + Impuls).
Kein Zeit-/Zufalls-Input → gleicher Zustand + gleicher Impuls = gleicher Narrator/Mood.

**Zustandsmaschine:** `.doki/session.json` — `idle → prepared (prepare) → verified (finish) → idle (finalize)`.

#### Der Composite-Hash (5 Felder)
```
c17j48n14a1p1
│  │  │  │ └─ p: RNG-Referenz auf einen Plot-Node (1..N)
│  │  │  └─── a: Arc-Index (aktuelle Handlungsphase)
│  │  └───── n: Narrator-Index (1-14, wählt den Charakter)
│  └──────── j: Jitter (bestimmt Mood + Struktur)
└─────────── c: Commit-Counter (seit Genesis, monoton)
```
Die fortlaufende Plot-ID `p_id` (p1, p2, …) ist die **Sequenz** — sie ist nicht das
RNG-gezogene `p`. Der Unterschied: `p_id` verankert jeden Chain-Eintrag eindeutig,
`p` ist eine inhaltliche Referenz (wie im JS-Original).

#### Die 14 Charaktere (selektiert via `n % 14`)
| # | Name | Rolle | Stil |
|---|------|-------|------|
| 1 | Buffy | Orchestrator | Zynisch-präzise, Problem→Analyse→Fix→Wirkung |
| 2 | Basher | Terminal Bot | Maschinell, CLI-Output-Ästhetik, Statuszeilen |
| 3 | Thinker | Analyse-Agent | Methodisch, Trade-offs, Kontext→Analyse→Fazit |
| 4 | Vannon | User/Regisseur | Direktiv, Imperative, keine Rechtfertigungen |
| 5 | Squizzle | Forensiker | Detektiv-Logbuch: Spuren→Indizien→Rekonstruktion |
| 6 | Devin | Architekt | Pattern erkennen, Schichten, neu vernähen |
| 7 | Argos | Lokaler Techniker | Bissig, bodenständig, 'Hab ich doch gesagt' |
| 8 | Ghost | Chronist | Feierlich, archivarisch, Datum→Ereignis→Bedeutung |
| 9 | Spark | Der Neue | Neugierig, fragend, laut denkend |
| 10 | Glitch | Verschwörungstheoretiker | Paranoid, Verbindungen, 'Zufall? Ich denke nicht.' |
| 11 | Null | Nihilist | Resigniert, philosophisch, existenzielle Einsichten |
| 12 | Echo | Archivar | Erinnert sich an alles, Flashbacks, historische Vergleiche |
| 13 | Flux | Chaot | Stream-of-Consciousness, Abschweifungen, Gedankenstriche |
| 14 | Sage | Weise/Lehrer | Pädagogisch, 'Stell dir vor…', eine Lektion |

#### Die 10 Moods (Overlay, `j % 10`, nie zweimal hintereinander)
sachlich · sarkastisch · erschöpft · triumphierend · selbstironisch · neugierig ·
müde-zufrieden · alarmiert · trocken · warm

#### Arc-Steuerung (Kategorie-basiert, seit v0.2)
Der ArcEngine kennt die **Impuls-Kategorie** (`classify_impulse`) und gewichtet danach:

| Kategorie | Arc-Gewicht | CLIMAX möglich? |
|-----------|-------------|-----------------|
| CODE, FEATURE | 0.5 Basis (voll) | ✅ |
| REFACTOR, BUILD | 0.25 Basis (halb) | ✅ (langsamer) |
| FIX, DOKU, TRIVIAL, TEST-ASSET | 0.0 (kein Beitrag) | ❌ nie |

Ein Bugfix löst also **kein** Staffelfinale aus — der Prompt unterscheidet
"STAFFELFINALE" (eligible) vs. "WARTUNGSABSCHNITT" (FIX/DOKU/Trivial).

#### 9 Checks (1-6 weich, 7-9 HARTER BLOCK)
1. Token-Länge + Pflicht-Tokens (Charakter-Regeln) · 2. Impuls-Integration ·
3. Storytelling (kein Bullet-Überhang, Konnektoren) · 4. Narrator-Token == Composite-n ·
5. Composite-Format == Session · 6. Cross-Narrator (Vorgänger erwähnt) ·
7. **Kausalität** (IMPULSE-Anker, Composite-Nachfolger) · 8. **DocSync**
(CHANGELOG/Index sauber, keine ungestagten Diffs) · 9. **ChainAudit**
(c/p monoton, RNG-Replay == Session).

#### Kernkommandos
```bash
$GODOT_BIN --headless --path . --script res://scripts/doki/doki.gd -- init --seed-last 10   # Genesis + letzte 10 Commits als Chain-Vorgeschichte
$GODOT_BIN --headless --path . --script res://scripts/doki/doki.gd -- status
$GODOT_BIN --headless --path . --script res://scripts/doki/doki_analyze.gd                  # Qualitäts-Analyse (Befunde: Fehler/Warnungen)
$GODOT_BIN --headless --path . --script res://scripts/doki/doki_selfcheck.gd                # 35 Regressionstests
$GODOT_BIN --headless --path . --script res://scripts/doki/doki_story_test.gd               # 5-Commits-E2E (NUR im Test-Worktree!)
```
**Full-Ref:** `scripts/doki/README.md` | CLI: `doki init|prepare|finish|amend|verify-only|finalize|repair|status|gate`

---

## 📦 ARCHITEKTUR & SYSTEM-VERTRÄGE (Referenz)

### Szenen-Architektur (3 Spiele, 1 SSO)
| Szene | Layer | Zweck |
|-------|-------|-------|
| `scenes/main_menu/main_menu.tscn` | Einstieg | Neues Spiel / Weiter / Beenden |
| `scenes/world/world.tscn` | 1 (Overworld) | `WorldBootstrap` + `PlanetField` + `MeteorField` + `MapCamera` + `PauseMenu` |
| `scenes/battle/battle_scene.tscn` | 2 (Flotten) | `FleetBattleSimulator` + `BattleScene` + `IngamePlayerControls` |
| `scenes/conquest/conquest_scene.tscn` | 3 (Eroberung) | `ConquestSimulator` + `ConquestScene` |

**SSO:** `GameState` (Autoload) — 4 Domänen: `FactionDomain`, `EconomyDomain`, `TechDomain`, `ShipDomain`.

### Wichtige Konventionen
- **Save Slots:** Slot 0 = echter Spielstand (nie im Preflight löschen!), Slots 1–7 = Test-Slots
- **Seed:** Preflight erzwingt `PREFLIGHT_LAYOUT_SEED = 424242` (deterministisch)
- **Chunk-Welt:** Beide Shipped-Szenarien sind unendlich (`chunk_size > 0`)
- **Sector-System:** Nur visuell (`planet_visual_scale`), nie `set_size_profile` ändern

---

## 🔍 SUCHE & CODE-NAVIGATION (Detail)

### ConceptIndex — Semantische Suche (Architektur)
```bash
# Im Code:
ConceptIndex.new().search("fleet")      # → Array[ConceptEntry]
ConceptIndex.new().expand("economy")    # → alle Economy-Konzepte
ConceptIndex.new().class_concept("ShipManager")
ConceptIndex.new().by_domain("ships")
```

**Wartung (neue class_name-Skripte):**
1. In `_build_concepts()` unter passendem Konzept in `class_names` eintragen
2. Datei-Mapping ist **automatisch** (Scan bei nächstem Preflight)
3. Synonyme im `synonyms`-Array ergänzen
4. Preflight prüft: `search()`/`expand()` funktionieren, Stale → nur Warning

### Global Search — Volltext über ALLE Formate
```bash
# Scannt rekursiv res:// — .gd, .tres, .tscn, .gdshader, .import, .json, .csv, .md, .txt, .cs, .glsl, .shader, ...
# Output: JSON mit file, type, matches[{match_line, context[{line, content, is_match}]}]
```

**When-to-use:**
| Frage | Tool |
|-------|------|
| "Welche Klassen für Fleet-Logik? Freie Slots? Domäne?" | **ConceptIndex** |
| "Wo kommt 'fleet_supply_bonus' in .tres/.tscn/.md vor?" | **Global Search** |
| "Gibt es Klasse 'FleetManager'?" | **ConceptIndex --class** |
| "Alle Dateien mit 'worker_transport'" | **Global Search** |
| "Suche nach A oder B (OR-Suche)" | Beide: `"a|b"` mit Pipe-Syntax |
| "Welche Zeilen kommen wie oft vor?" | **Global Search --freq** |
| "Dead-Code-Kandidat? func definiert aber nicht aufgerufen?" | **Global Search --defs** |
| "Capture-Groups extrahieren (z.B. Funktionsnamen)" | **Global Search --regex** |
| "Zu viele Treffer → Timeout" | **Global Search --max-files 500** |

---

## ⚙️ PREFLIGHT-SUITE (Detail)

### CLI-Optionen
| Flag | Zweck |
|------|-------|
| `-v, --verbose` | Detail-Assertions |
| `-x, --fail-fast` | Abbruch bei erstem Fehler |
| `-f, --filter=<name>` | Nur Constraints mit Substring (z.B. `fleet`, `save`) |
| `--reverse` | Reverse-Execution (Testet Isolation) |
| `-l, --list` | Alle 36 Constraints auflisten |

### Constraints (36, atomare Commit-Gruppen beachten!)
- `game_state_compatibility` — Reflection-Signaturen, Fassaden-Methoden
- `concept_index` — **Nur funktional**: search/expand für Kern-Domänen
- `save_game_roundtrip`, `save_game_slots` — Slot-Konvention beachten!
- `mechanic_coverage` — Auto-Erkennung neuer Mechaniken
- ... (siehe `--list`)

---

## 🏗️ ATOMARE COMMIT-GRUPPEN (Change Together)

| Bereich | Dateien (müssen gemeinsam commitet werden) |
|---------|---------------------------------------------|
| **Transit & Dispatch** | `flight_time.gd`, `dispatch.gd`, `planet_network.gd`, `worker_cluster.*`, `worker_manager.gd`, `game_state.gd`, `preflight.gd` |
| **Navigation** | `navigation_field.gd`, `navigation_waypoint.gd`, `seeded_layout.gd`, `planet_network.gd`, `worker_manager.gd`, `preflight.gd` |
| **Planeten & Katalog** | `planet.tscn`, `planet.gd`, `planet_arrival_resolver.gd`, `planet_trait_aggregator.gd`, `planet_view.gd`, `seeded_layout.gd`, Configs & SVGs |
| **GameState & Ressourcen** | `game_state.gd`, `scripts/state/domains/*`, `resource_pool*.tres`, `bootstrap.gd`, `preflight.gd` |
| **Schiffsbau & Forschung** | `ship_part_definition.gd`, `ship_blueprint.gd`, `ship_part_catalog.gd+tres`, `technology_definition.gd`, `ship_manager.gd`, `dossier/workshop_view.gd`, `dossier/parchment_tech_tree_view.gd`, `preflight.gd` |
| **Kampf & Simulation (L2/3)** | `fleet_battle_simulator.gd`, `conquest_simulator.gd`, `battle_scene.gd`, `conquest_scene.gd`, `composite_ship_view.gd`, `conflict_manager.gd`, `fleet_snapshot.gd`, `preflight.gd` |
| **Prozedurale Welt** | `world_config.gd`, `world_generator.gd`, `chunk_coordinator.gd`, `planet_procedural.gd`, `navigation_field.gd`, `preflight.gd` |
| **SectorSystem** | `sector_flavor.gd`, `sector_anchor.gd`, `sector_classifier.gd`, `sector_flavor_catalog.gd`, `world_config.gd`, `seeded_layout.gd`, `preflight.gd` |
| **Save/Load** | `save_game_service.gd`, `run_save_data.gd`, `game_state.gd`, `scripts/state/domains/*`, `seeded_layout.gd`, `pause_menu.gd`, `main_menu.gd`, `preflight.gd` |
| **ConceptIndex & Suche** | `concept_index.gd`, `constraint_concept_index.gd`, `mechanic_registry.gd`, `scenario_loader.gd`, `scenario_snapshot.gd`, `preflight.gd` |
| **Global Search** | `global_search.gd`, `AGENTS.md` |
| **DOKI CommitLayer** | `scripts/doki/**`, `narrative_chain.json`, `change_index.json`, `CHANGELOG.md`, `.githooks/pre-commit`, `.githooks/commit-msg`, `.githooks/post-commit`, `AGENTS.md`, `scripts/concept_index.gd` |

---

## 🐛 GODOT-FALLSTRICKE (Kurz)

- `@export_enum` → String/Integer, **nicht** `StringName`
- Resource/Waypoint-Skripte für `@tool` → **auch** `@tool`
- `NavigationWaypoint.configure()` läuft **vor** `_enter_tree()` — kein `@onready`
- `MultiMeshInstance2D` braucht `MultiMesh.mesh` (QuadMesh) **vor** `instance_count`
- `SceneTree.quit()` → **danach `return`** nötig
- `.uid`-Sidecars (`*.gd.uid`) **mitcommitten** (nicht in `.gitignore`)
- Neue `class_name` → Editor-Scan: `$GODOT_BIN --headless --path . --editor --quit`
- `Node.name` = `StringName` → für String-Ops: `String(node.name)`
- `class_name` als Parametername **verboten** (Parser-Fehler) → `cls_name` nutzen
- Instanz-Methode `func load()` **verboten** (kollidiert mit globalem `load(path)`) → `read()` nutzen
- `OS.is_stdin_connected()` existiert in 4.7 NICHT → stdin nur mit explizitem `--stdin` Flag
- `is_instance_valid()` unzuverlässig bei gerade `free()` → `v.get_class()` crasht
- `StreamPeerTCP.get_data()` → `Array[Error, Daten]`, nicht `PackedByteArray`
- `RefCounted` hat **kein** `get_node_or_null()` → `Engine.get_main_loop().root.get_node_or_null()`

---

## 📋 WORKFLOW ZUSAMMENFASSUNG

### AM ANFANG (jeder Task)
1. `GODOT_BIN` setzen
2. **ConceptIndex** nutzen: `concept_search.gd --domain <xyz>` / `--class <Name>` / `--free-slots`
3. **Global Search** für Volltext: `global_search.gd "term" --type tres,tscn`
4. Relevante Dateien lesen (`read_file`), **nicht** raten

### ZWISCHENDURCH
- Kleine, atomare Änderungen
- Nach jeder logischen Einheit: `git add <dateien>` + `git commit` mit Begründungszeilen
- Preflight läuft automatisch im Hook
- **MCP-Läufe (sichtbar):** Standard-Transport ist `mcp_file_driver.js` (eine Befehlszeile = genau ein Tool-Call, Latenz ~4–16 ms; Nutzung siehe `MCP_INDEX.md` → Schnellstart). Kein FIFO-/Session-Basteln mehr.
- **Nie bei unerwarteten Ergebnissen raten:** Fehler (`ok:false`, `_error`, „Node not found"), daneben gegangene Klicks (`clicked:false`) und leere Scans (`controls:[]`) hängt der MCP-Server **automatisch** `visual_evidence` an (Screenshot + OCR). Daraus den echten Bildschirmzustand ableiten — nicht spekulieren.

### AM ENDE (nach Arbeit)
1. **Full Preflight**: `$GODOT_BIN --headless --path . --script res://scripts/preflight.gd -x`
2. `git status` / `git diff` prüfen (Headless formatiert .tscn/.tres, injects uids)
3. `.uid`-Sidecars für neue Scripts mitcommitten
4. Push erfolgt via `post-commit` Hook automatisch

---

## 🔗 WEITERE DOKS
- **`docs/FINDINGS.md` — ZENTRALE FINDINGS-DATEI (Pflicht, IMMER aktuell halten!)** —
  Jeder QA-Lauf/Fix wird dort nachgetragen (Status ✅ GEFIXT / 🟡 OFFEN / 🔵 BEOBACHTET,
  Beleg, Referenz). Die Datei ist Todo-Referenz der Befunde und wird **mitcommittet**.
- `DESIGN.md` — Feature-Status, Umsetzungsplan
- `VISION.md` — Spielkreislauf, Layer-Details
- `scripts/testing/SCENARIO_LOADER_SPEC.md` — ScenarioLoader API
- `addons/gdscript_mcp/` — MCP-Remote-Testing (E2E, Playthrough-Archiv)
- `scripts/doki/README.md` — DOKI CommitLayer (Commit-Gate, Flow, Checks, Recovery)