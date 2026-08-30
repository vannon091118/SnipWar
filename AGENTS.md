# SnipWar Agent Notes
EWS GIBT KEIN HARMLOS , IRRLEVANT, UNGEFÄährlich IN DIESER REPO KEINE SKIPS KEINE WORKAROUNDS UND AUUCH KEINE ERWARTTE FEHLER DIE NICHT DIREKT BEHOBEN WERDEN! WIR FÜHREN KEIN BACKLOG TOO ODER "SPÄER MACHEN" DIREKTE UMSEZUNG ALLER ROOT CAUSE ANALYSN INKL LANGFRISTIGE STABILE LÖSUNNFGS IMPLMETIERUNG AUSAHMLOS EGAL WIE TIVIAL

SOBALD EIN VERTRAG oder REGEL EBROCHEN WUDE ROLLBACK NEU BEGINN AUSNAHMSLOS


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
**Agent-code_search (Harness ripgrep):** `-t gd` wird nicht erkannt ("unrecognized file type") → Dateifilter immer als `-g *.gd`.

### 3. Preflight (Verbindlicher Qualitäts-Check)
```bash
$GODOT_BIN --headless --path . --script res://scripts/preflight.gd -x   # Full Suite (44 Constraints, ~64s, V2 Architecture)
$GODOT_BIN --headless --path . --script res://scripts/preflight.gd --filter=concept_index -v  # Einzelne Constraint
$GODOT_BIN --headless --path . --script res://scripts/preflight.gd --scope=.doki/scope.json  # Machine-resolvable Scope (Hook)
```
**Verbindlich:** `RESULT: PASSED` — ERROR-Traces am Ende sind normales Headless-Rauschen.
**Session-Scoped Verification:** `--scope` ist der einzige autoritative Scoped-Modus. Das Manifest
wird von `doki prepare` über `scripts/preflight_v2/change_impact_resolver.gd` aus dem echten Diff
erzeugt (Pfad → Contract → Constraint-Closure, deterministisch & fail-closed). Empty/Unknown/
Duplicate-Scope blockt (nie ein grüner 0-Constraint-Run). Ohne Manifest läuft der volle Full-Preflight.
Der pre-commit Hook nutzt `.doki/scope.json`, wenn vorhanden, sonst Full. Kanonisches Impact-
Metadata liegt in `scripts/preflight_v2/constraint_scanner.gd` (keine Parallel-Registry).
**V2 Features:** Auto-Discovery, Phase-Split (Pure/Scene), Fail-Fast mit Summary, Isolation Warnings.
**Legacy V1:** `scripts/legacy/preflight_v1.gd` wurde in `ab080dc` entfernt (kein aktives Archiv — V2 IST die Kanonische).

### 4. Commit-Workflow (Hooks aktiv, DOKI CommitLayer als Tor!)
```bash
# JEDER Commit läuft durch den DOKI-Flow (sonst blockt pre-commit):
git add <datei1> <datei2> ...                 # NIEMALS git add -A / .
$GODOT_BIN --headless --path . --script res://scripts/doki/doki.gd -- prepare "<impuls>"
#   → liest .doki/prompt.txt: Narrator + Mood + Composite (deterministisch)
#   → Agent schreibt den Commit-Body in der Rolle des Narrators (Fließtext)
$GODOT_BIN --headless --path . --script res://scripts/doki/doki.gd -- finish --body-file .doki/narrator_body.md
#   → 10 Checks (1-6 weich, 7-10 HART), schreibt .commit_msg.txt + staged Doku-Artefakte
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

#### 10 Checks (1-6 weich, 7-10 HARTER BLOCK)
1. Token-Länge + Pflicht-Tokens (Charakter-Regeln) · 2. Impuls-Integration ·
3. Storytelling (kein Bullet-Überhang, Konnektoren) · 4. Narrator-Token == Composite-n ·
5. Composite-Format == Session · 6. Cross-Narrator (Vorgänger erwähnt) ·
7. **Kausalität** (IMPULSE-Anker, Composite-Nachfolger) · 8. **DocSync**
(CHANGELOG/Index sauber, keine ungestagten Diffs) · 9. **ChainAudit**
(c/p monoton, RNG-Replay == Session) · 10. **Datei-Limit/Atomicity**
(max. 30 User-Dateien pro Commit; Auto-Managed narrative Dateien zählen nicht).

#### Kernkommandos
```bash
$GODOT_BIN --headless --path . --script res://scripts/doki/doki.gd -- init --seed-last 10   # Genesis + letzte 10 Commits als Chain-Vorgeschichte
$GODOT_BIN --headless --path . --script res://scripts/doki/doki.gd -- status
$GODOT_BIN --headless --path . --script res://scripts/doki/doki_analyze.gd                  # Qualitäts-Analyse (Befunde: Fehler/Warnungen)
$GODOT_BIN --headless --path . --script res://scripts/doki/doki_selfcheck.gd                # 65 Regressionstests
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

### MCP Sync/Async-Dispatch-Vertrag (verstecktes Routing)
- `mcp_server.gd` routet per `_async`-Flag der Tool-Def: nicht-async → sync `dispatch`, async → `_run_async_tool`/`dispatch_async` (UX-Module haben **beide** Dispatch-Surfaces).
- Handler, der suspendieren kann (Screenshot wartet auf `frame_post_draw`): `_async=true` + Arm in `dispatch_async` + sync-Arm lehnt mit "async-only"-Error ab — sonst liefert der Sync-Pfad ein `GDScriptFunctionState` statt Dictionary.
- Neues `await` in einer Funktion macht ALLE Aufrufer ohne `await` still kaputt (FunctionState; folgendes `.get()/.has()` darauf bricht die Funktion → null, kein Crash). Gates: `mcp_capture_contract` + `scripts/testing/mcp_capture_entry_test.gd`.

### Narrative Runtime (Python) — abgeleitete State-Welt
**Vertrag (verbindlich):** `scripts/doki/NARRATIVE_ENGINE_DESIGN.md` (Sprint 0, Rev. 2).
- **Git/DOKI bleibt Wahrheit** (Git-Historie, `narrative_chain.json`, `change_index.json`, DOKI-Session). Die Runtime (`narrative_runtime/`, Python ≥ 3.11, **stdlib-only**) leitet nur ab: ChainObservations → später Relationships/Beliefs/Threads/Perspectives/Candidates. SQLite (`narrative_runtime/state/`, gitignored) ist rekonstruierbares Archiv, nie zweite Wahrheit.
- **Nie blockierend:** Runtime-Fehler dürfen prepare/finish/commit/finalize nie berühren; Anbindung erst post-push (best-effort), geplant vor Sprint 7 hinter dem **NARRATIVE_RUNTIME_GATE** (fail-closed: stdlib-only, Purity, Event-ID-Reproduzierbarkeit, Chain-Lücken, State-schreibt-Git, Idempotenz, Rebuild == Incremental).
- **Chain-Anker:** Meta speichert `last_processed_chain_seq` + `commit_hash` + `entry_digest` — rebase/amend-Rewrite an derselben Seq ⇒ HISTORY CHANGED (Exit 2), Rebuild Pflicht, kein stiller Skip.
- **Composite unberührt:** Runtime berechnet niemals Composite/Narrator-Auswahl (`n`/`j`) neu.
- **CLI:** `python -m narrative_runtime import|rebuild|verify|status` (Exit-Codes: 0 ok · 2 Rebuild erforderlich · 3 Chain ungültig · 1 sonstig).

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
| `--list` | Constraints auflisten — **Kurzform `-l` kollidiert mit Godots eigenem `-l/--language`** ("Missing language argument, aborting") → Langform nutzen |

### Constraints (44, atomare Commit-Gruppen beachten!)
- `game_state_compatibility` — Reflection-Signaturen, Fassaden-Methoden
- `concept_index` — **Nur funktional**: search/expand für Kern-Domänen
- `save_game_roundtrip`, `save_game_slots` — Slot-Konvention beachten!
- `mechanic_coverage` — Auto-Erkennung neuer Mechaniken
- `mcp_capture_contract` — get_image() nur nach `frame_post_draw` in derselben Funktion, Sync-Umgehung `capture_screenshot_sync` verboten, Screenshot-Tools `_async=true`
- ... (siehe `--list`)
- **Quelltext-Scanner (Constraints/grep-Gates) müssen `#`-Kommentarzeilen überspringen** — sonst Fehlverstoß (Kommentarzeile als Code gelesen) oder false-pass (`frame_post_draw` nur im Kommentar)

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
| **Narrative Runtime (Python)** | `narrative_runtime/**`, `.gitignore`, `scripts/doki/NARRATIVE_ENGINE_DESIGN.md`, `AGENTS.md` |

---

## 🐛 GODOT-FALLSTRICKE (Kurz)

- `@export_enum` → String/Integer, **nicht** `StringName`
- Resource/Waypoint-Skripte für `@tool` → **auch** `@tool`
- `NavigationWaypoint.configure()` läuft **vor** `_enter_tree()` — kein `@onready`
- `MultiMeshInstance2D` braucht `MultiMesh.mesh` (QuadMesh) **vor** `instance_count`
- **`Array.map()` → typisiertes Array:** `Array.map()` liefert untypisierte Arrays — Zuweisung an `Array[StringName]`-Felder crasht zur Laufzeit (489 SCRIPT ERRORS beim Chronicle-Restore, Phase 1). Explizit typisierte Schleife nutzen: `var out: Array[StringName] = []; for x in src: out.append(x)`
- **Config-Resource → Autoload-Zyklus:** Config-Klassen (`.tres`-geladen, von GameState preloadet) dürfen `GameState`-Konstanten NICHT als Default-Werte referenzieren — Compile-Zyklus `GameState → .tres → Config → GameState` bricht je nach Ladereihenfolge. Lösung: dependency-freie `GameConstants` (`scripts/config/game_constants.gd`)
- **UID-Alphabet (Base32, 0-9a-v):** UIDs mit Zeichen außerhalb (z.B. `y/x/w`) werden vom Editor verworfen → `.tres`-Referenz unauflösbar. Sidecar-UIDs mit `--editor --quit` regenerieren lassen
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
- Headless: `get_visible_rect()` → (0,0), keine `current_scene` (`scene="unknown"`) → UI-Test-Assertions dürfen nicht von Fenstergeometrie/Scene-Namen abhängen
- `McpVisionCapture.capture_screenshot` prüft Viewport-Textur VOR `await frame_post_draw` → headless deterministischer Capture-Error statt Hang; Await auf Coroutine, die ohne Suspension returned, resolved sofort

---

## 📋 PFLICHT-WORKFLOW (erzwungen, keine Ausnahmen)

### Grundregel
```
JEDER Commit MUSS durch den DOKI-Flow laufen.
KEIN git commit -m, KEIN --no-verify, KEIN Skip.
Pre-commit Hook blockt Verstöße (Exit 1).
```

### Der Workflow-Loop
```
┌─────────────────────────────────────────────────────┐
│  1. SELECT    Roadmap lesen → nächsten Slice wählen │
│  2. VERIFY-*  Vorher-Zustand prüfen (grep/read)     │
│  3. IMPLEMENT Minimale Änderung für den Slice       │
│  4. GATE      compile_gate → Tests → Preflight      │
│  5. DOCS      ROADMAP + FINDINGS aktualisieren      │
│  6. DOKI      prepare → body → finish → commit      │
│  7. RE-AUDIT  git status, Regression, nächster Loop  │
└─────────────────────────────────────────────────────┘
```

### 1. SELECT — Slice aus Roadmap wählen
```bash
cat ROADMAP.md  # Offene Tasks nach PRIORITY/DEPENDENCY lesen
```
- Höchste Priorität ohne Blocker wählen
- Nicht automatisch den ältesten Task nehmen
- Bei Ambiguität: STOP + Bericht

### 2. VERIFY-* — Vorher-Zustand dokumentieren
```bash
# ConceptIndex für Architektur:
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --domain <xyz>
$GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --class <Name>
# Global Search für Volltext:
$GODOT_BIN --headless --path . --script res://scripts/global_search.gd "term" --type tres,tscn
# Dateien lesen, NICHT raten:
read_file der betroffenen Dateien
```

### 3. IMPLEMENT — Minimale atomare Änderung
- NUR den gewählten Slice implementieren
- Keine parallelen Refactors, keine Kosmetik
- Neue `.class_name` → Editor-Scan: `$GODOT_BIN --headless --path . --editor --quit`
- `.uid`-Sidecars für neue Scripts erzeugen

### 4. GATE — Verifikation (PFLICHT, keine Ausnahmen)
```bash
# a) Compile (alle Scripts):
$GODOT_BIN --headless --path . --script res://scripts/testing/compile_gate.gd
# b) Spezifische Tests:
$GODOT_BIN --headless --path . --script res://scripts/testing/test_all.gd
# c) Preflight (44 Constraints):
$GODOT_BIN --headless --path . --script res://scripts/preflight.gd -x
```
- **RESULT: PASSED** ist Pflicht
- ERROR-Traces am Ende sind Headless-Rauschen, ignorieren
- Bei FAIL: fixen, neu stagen, Gate wiederholen

### 5. DOCS — ROADMAP + FINDINGS synchron halten
- ROADMAP: Status des Slices → `VERIFIED`
- FINDINGS: geschlossene Findings → `GEFIXT`, neue → `OFFEN`
- Constraint-Zahlen in allen Docs aktuell (aktuell: 44)

### 6. DOKI — Commit-Flow (UNTERBRECHUNGSLOS)
```bash
# a) Stagen (NIEMALS git add -A):
git add <datei1> <datei2> ...

# b) DOKI prepare:
$GODOT_BIN --headless --path . --script res://scripts/doki/doki.gd -- prepare "<impuls>"

# c) Narrator-Body schreiben (Fließtext, keine Bullets):
# → .doki/narrator_body.md

# d) DOKI finish:
$GODOT_BIN --headless --path . --script res://scripts/doki/doki.gd -- finish --body-file .doki/narrator_body.md

# e) Commit (DOKI erzeugt .commit_msg.txt):
git commit -F .commit_msg.txt
```
- **VERBOTEN:** `git commit -m "..."` ohne DOKI-Flow
- **VERBOTEN:** `--no-verify` (bypassed DOKI + Preflight-Hook)
- **VERBOTEN:** Direkt-Commits ohne prepare/finish
- Begründungszeilen (`- pfad/datei: Grund.`) erzeugt DOKI maschinell
- DOKI-Artefakte (CHANGELOG, change_index, narrative_chain, arcs) werden
  vom post-commit-Hook aktualisiert — diese NÄCHSTEN Commit mitnehmen

### 7. RE-AUDIT — Nach jedem Commit
```bash
git status          # Working Tree sauber?
git log --oneline -1 # Commit korrekt?
```
- Neue Dead-Code-Kandidaten?
- Neue Doku-Drift?
- Regression in Consumers/Producers?
- Bei neuen Problemen: neues Finding in FINDINGS.md

### Compile-Gates (headless, Pflicht)
`scripts/testing/compile_gate.gd` kompiliert JEDE .gd in scripts+addons.
Entry-Point-Falsifizierung über die ECHTE Registry:
`scripts/testing/chain_validate_entry_test.gd`,
`scripts/testing/mcp_capture_entry_test.gd`
(Evidence-JSON → `user://mcp_evidence/`; Exit 1 = Abweichung)

### MCP-Tests (sichtbar)
**Pflicht-Lektüre:** `addons/gdscript_mcp/AGENTS.md`
(MCP-Test-Doktrin: Standard-Transport, OCR-Pflicht, Entkopplung, Atom-Vertrag)
MCP-Findings → `docs/FINDINGS.md` (Abschnitt „MCP-Findings")

---

## 🔗 WEITERE DOKS
- **`docs/FINDINGS.md` — ZENTRALE FINDINGS-DATEI (Pflicht, IMMER aktuell halten!)** —
  Jeder QA-Lauf/Fix wird dort nachgetragen (Status ✅ GEFIXT / 🟡 OFFEN / 🔵 BEOBACHTET,
  Beleg, Referenz). Die Datei ist Todo-Referenz der Befunde und wird **mitcommittet**.
- `ARCHITECTURE.md` — Technische Systemarchitektur, Godot 4.7 Specs, Domain-Manager & Preflight-Suite
- `DESIGN.md` — Feature-Status, Umsetzungsplan
- `VISION.md` — Spielkreislauf, Layer-Details
- `scripts/testing/SCENARIO_LOADER_SPEC.md` — ScenarioLoader API
- **`addons/gdscript_mcp/AGENTS.md` — PFLICHT-LESE für MCP-Tests** (MCP-Doktrin:
  Transport, OCR, Entkopplung, Atom-Vertrag — getrennt von dieser Datei)
- `addons/gdscript_mcp/` — MCP-Remote-Testing (E2E, Playthrough-Archiv; Doku im Addon)
- `scripts/doki/README.md` — DOKI CommitLayer (Commit-Gate, Flow, Checks, Recovery)
- `scripts/doki/NARRATIVE_ENGINE_DESIGN.md` — Narrative Runtime Verträge (Sprint 0): Schichtmodell 0–7, ChainObservation-Schema, Chain-Anker, SQLite-Vertrag, gerichtetes Beziehungsmodell, NARRATIVE_RUNTIME_GATE
