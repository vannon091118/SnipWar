# ScenarioLoader — READ-Only Test-Modul

## Architektur

```
scripts/testing/
├── mechanic_registry.gd      # Reflection-basierte Discovery
├── scenario_snapshot.gd       # READ-Only Resource
└── scenario_loader.gd         # Statischer Loader

resources/scenarios/
├── scenario_early_basic.tres
├── scenario_mid_tech_ships.tres
├── scenario_late_combat.tres
└── scenario_crisis_homeworld.tres

resources/test_models/         # (optional) Mechanik-Test-Modelle
└── mechanic_<signal_name>.tres
```

**READ-Only-Vertrag:** Weder `MechanicRegistry`, `ScenarioSnapshot` noch `ScenarioLoader` verändern den Spielzustand ohne expliziten `apply_snapshot()`-Aufruf. Die Snapshot-Ressourcen selbst werden nie mutiert.

---

## Komponenten

### 1. MechanicRegistry

Reflection-basierte Discovery aller Spielmechaniken über `GameState.get_signal_list()`.

```gdscript
var registry := MechanicRegistry.new()

# Alle entdeckten Mechaniken
var all := registry.get_all()  # Array[MechanicEntry]

# Nur eine Domäne
var economy := registry.get_by_domain(&"economy")

# Unbekannte / unregistrierte
var unregistered := registry.discover_unregistered()

# Kaputte Test-Modelle
var broken := registry.discover_broken_models()

# Zusammenfassung
print(registry.summary())
# → "34 mechanics discovered, 28 registered, 6 unregistered"
```

**MechanicEntry-Struktur:**

| Feld | Typ | Beschreibung |
|------|-----|-------------|
| `id` | `StringName` | Signal-Name (= Mechanik-Identifier) |
| `description` | `String` | Menschlich lesbar |
| `domain` | `StringName` | `economy`, `tech`, `ship`, `faction`, `combat`, `world` |
| `test_model_path` | `String` | Pfad zum Test-Modell, `""` = keines |
| `verified` | `bool` | Ob das Test-Modell validiert wurde |

**Discovery-Logik:**

1. Lädt `GameState`-Script via `preload()`
2. Instanziiert temporären Node für `get_signal_list()`
3. Mappt jedes Signal auf `MechanicEntry` mit Domäne + Beschreibung
4. Prüft ob `res://resources/test_models/mechanic_<signal>.tres` existiert

**Domänen-Zuordnung (`_populate_domain_hints`):**

| Signal | Domäne |
|--------|--------|
| `faction_resources_changed`, `credits_changed`, `gathering_*`, `worker_factory_built`, `refinery_converted`, `building_placed`, `building_removed` | `economy` |
| `faction_changed`, `planet_discovered`, `planet_scanned`, `milestone_reached` | `faction` |
| `technology_researched`, `planet_technology_researched`, `research_started` | `tech` |
| `ship_assembled`, `ship_launched`, `ship_lost`, `ship_build_started`, `persistent_ship_changed` | `ship` |
| `battle_context_changed` | `combat` |
| `catalog_reset`, `mid_game_started` | `world` |

**Neue Mechaniken erkennen:**

Wenn ein neues Signal zu `GameState` hinzugefügt wird, findet die Registry es automatisch. Die Beschreibung fällt auf `"Unknown mechanic — add description to _describe_signal()"`. Der Preflight-Constraint warnt dann.

---

### 2. ScenarioSnapshot

READ-Only Resource die einen Spielzustand + Metadaten kapselt.

```gdscript
# Überprüfen ob ein Scenario gültig ist
var snapshot: ScenarioSnapshot = load("res://resources/scenarios/mid_tech_ships.tres")
if snapshot.is_valid():
    print(snapshot.summary())
    # → "[mid] Mid Game — Tech & Ships — 18 mechanics, tags: world, faction, economy, tech, ship"
```

**Felder:**

| Feld | Typ | Beschreibung |
|------|-----|-------------|
| `scenario_id` | `StringName` | Eindeutige ID |
| `display_name` | `String` | Anzeigename |
| `description` | `String` | Beschreibung |
| `phase` | `StringName` | `early`, `mid`, `late`, `crisis`, `custom` |
| `mechanics_covered` | `Array[StringName]` | Signal-Namen die das Scenario testet |
| `tags` | `Array[StringName]` | Filter-Tags |
| `save_data` | `RunSaveData` | Der eigentliche Spielzustand |
| `layout_seed_override` | `int` | Seed-Override (-1 = keiner) |

**Validierung:**

```gdscript
var errors := snapshot.validate()
if not errors.is_empty():
    push_error("Invalid: " + "; ".join(errors))
```

---

### 3. ScenarioLoader

Statischer Loader der Snapshots auf GameState anwendet.

```gdscript
# Aus Datei laden
var result := ScenarioLoader.load_scenario("res://resources/scenarios/early_basic.tres")
if result.ok:
    # GameState ist jetzt im Frühspiel-Zustand
    run_my_test()
else:
    push_error(result.error)

# Aus vor geladenem Snapshot
var snapshot: ScenarioSnapshot = load(path)
var result := ScenarioLoader.apply_snapshot(snapshot)

# Verfügbare Scenarios auflisten
var files := ScenarioLoader.list_available()
for f in files:
    print(f)

# Coverage analysieren
var coverage := ScenarioLoader.mechanic_coverage(snapshot)
print("Coverage: %.0f%%" % (coverage.coverage_ratio * 100))
print("Uncovered: %s" % str(coverage.uncovered))
```

**LoadResult-Struktur:**

| Feld | Typ | Beschreibung |
|------|-----|-------------|
| `ok` | `bool` | Erfolgreich geladen |
| `error` | `String` | Fehlermeldung bei Misserfolg |
| `snapshot` | `ScenarioSnapshot` | Das geladene Snapshot |

**Lade-Reihenfolge:**

1. `load(resource_path)` → Lädt `.tres`-Datei
2. `validate()` → Prüft Metadaten
3. `_get_game_state()` → Findet GameState-Autoload
4. `set_layout_seed()` → Wendet Seed-Override an (falls gesetzt)
5. `restore_run(save_data)` → Stellt Spielzustand her

---

### 4. Preflight-Constraint (`mechanic_coverage`)

Läuft als Teil der Standard-Preflight-Suite. Registry-Eintrag in `preflight.gd`:

```gdscript
{
    "id": "mechanic_coverage",
    "script": preload("res://scripts/preflight/constraint_mechanic_coverage.gd"),
    "desc": "Mechanic discovery, test model integrity & scenario validation",
    "requires_scene": false,
},
```

**Was er prüft:**

1. ✅ `MechanicRegistry` entdeckt > 0 Mechaniken
2. ✅ Jede Mechanik hat eine Beschreibung (kein "Unknown")
3. ✅ Jede Mechanik ist einer Domäne zugeordnet
4. ✅ Test-Modelle existieren (keine kaputten Pfade)
5. ⚠️ Unregistrierte Mechaniken → Warning (kein Failure)
6. ✅ Mindestens eine Scenario-Datei existiert
7. ✅ Jede Scenario-Datei ist valide

**Ausführung:**

```bash
# Nur diesen Constraint
$GODOT_BIN --headless --path . --script res://scripts/preflight.gd -- -f=mechanic_coverage

# Mit Detail-Output
$GODOT_BIN --headless --path . --script res://scripts/preflight.gd -- -f=mechanic_coverage -v
```

---

## Convention: Scenario-Files erstellen

### Dateinaming

```
resources/scenarios/scenario_<phase>_<variant>.tres
```

Phasen: `early`, `mid`, `late`, `crisis`, `custom`

### Metadaten-Checkliste

Jede Scenario-Datei muss haben:

- [ ] `scenario_id` — eindeutig, `&"phase_variant"`
- [ ] `display_name` — menschlich lesbar
- [ ] `description` — was das Scenario testet
- [ ] `phase` — `early`/`mid`/`late`/`crisis`/`custom`
- [ ] `mechanics_covered` — alle Signal-Namen die geübt werden
- [ ] `tags` — Domänen-Tags für Filterung

### mechanics_covered befüllen

```gdscript
# 1. Registry fragen welche Mechaniken existieren
var registry := MechanicRegistry.new()
var all := registry.get_all()

# 2. Für jedes Signal prüfen ob es in diesem Scenario getestet wird
var covered: Array[StringName] = []
for mechanic in all:
    if_wird_getestet(mechanic.id):
        covered.append(mechanic.id)

# 3. In die .tres schreiben
# mechanics_covered = Array[StringName]([...])
```

---

## Integration mit bestehendem Code

### Preflight-Integration

Der Constraint läuft automatisch in der vollen Preflight-Suite. Er erkennt:

- **Neue Mechaniken:** Sobald ein Signal zu GameState hinzugefügt wird
- **Fehlende Beschreibungen:** Wenn `_describe_signal()` nicht aktualisiert wurde
- **Fehlende Domänen:** Wenn `_populate_domain_hints()` nicht aktualisiert wurde
- **Kaputte Test-Modelle:** Wenn eine .tres-Datei verschoben/gelöscht wurde

### Manuelle Nutzung

```gdscript
# In einem Test-Skript:
func _ready() -> void:
    var result := ScenarioLoader.load_scenario("res://resources/scenarios/mid_tech_ships.tres")
    if result.ok:
        # GameState ist jetzt im Mid-Game
        # Hier Feature testen
        _test_my_feature()

func _test_my_feature() -> void:
    var gs := get_tree().root.get_node("GameState")
    # ... Feature-Logik testen
    assert(some_condition)
```

### Mit Preflight-Fixture

```gdscript
# In einem Preflight-Constraint:
func run(ctx: PreflightContext) -> bool:
    var result := ScenarioLoader.load_scenario("res://resources/scenarios/late_combat.tres")
    if not result.ok:
        return ctx.check(false, "Could not load scenario: " + result.error)

    # GameState ist jetzt im Late-Game-Zustand
    # Feature testen
    var gs := ctx.root().get_node("GameState")
    ctx.check(gs.has_active_run(), "Run should be active after scenario load")
    return true
```

---

## Erweiterung: Neue Mechaniken

Wenn du eine neue Mechanik hinzufügst:

1. **Signal zu GameState hinzufügen**
2. **`_describe_signal()` in `mechanic_registry.gd` erweitern**
3. **`_populate_domain_hints()` in `mechanic_registry.gd` erweitern**
4. **Preflight-Constraint warnt automatisch** wenn Schritt 2/3 vergessen wurde
5. **(Optional) Test-Modell erstellen:** `res://resources/test_models/mechanic_<signal_name>.tres`

---

## Erweiterung: Neue Scenarios

1. **Neue `.tres`-Datei** in `resources/scenarios/` erstellen
2. **Script:** `scenario_snapshot.gd` als Base verwenden
3. **`save_data`** mit `RunSaveData` befüllen (oder `null` für reine Metadaten-Scenarios)
4. **`mechanics_covered`** mit relevanten Signal-Namen befüllen
5. **Preflight validiert automatisch** die neue Datei

---

## LSP/ES-Modell

Das System nutzt **kein externes LSP/ES-Modell**. Die Discovery basiert auf:

- **Godot Reflection:** `get_signal_list()` auf einer temporären GameState-Instanz
- **Statische Domänen-Zuordnung:** Hardcoded in `_populate_domain_hints()`
- **Datei-System-Check:** `ResourceLoader.exists()` für Test-Modelle

Ein LSP-basiertes Ansatz wäre möglich (Port 6006, TCP), erfordert aber:
- Godot-Editor mit aktiviertem LSP-Server
- Einen TCP-Client der `workspace/symbol` abfragt
- Aktuell nicht implementiert (niedrige Priorität, Reflection reicht)
