# SnipWar Game Cycle — Architektur-Konzept

> **Status:** Konzept-Scan, August 2026
> **Kernprinzip:** Drei eigenständige Szenen, eine persistente Welt, Pfadbasierte Taktik

---

## 1. Das Problem

Aktuell laufen alle drei Layer in EINER Szene (`starfield_background.tscn`):
- Layer 2 (`BattleScene`) und Layer 3 (`ConquestScene`) sind CanvasLayer-Overlays (80/85), die über die Overworld gezeichnet werden
- Kein echter Szenenwechsel — alles teilt sich denselben SceneTree
- Layer 2 ist nur Replay-Animation, kein aktives Gefecht
- Layer 3 fehlt komplett (keine Towers, keine Waves, keine Minions)
- Kein Victory/Defeat — das Spiel endet nie
- Kein Rückkanal: Überlebende aus Battle/Conquest kehren nicht strukturiert zurück

## 2. Die Vision: 3 Spiele in derselben Welt

```
┌─────────────────────────────────────────────────────────────────────┐
│                    GAME STATE (Autoload)                            │
│  FactionDomain · EconomyDomain · TechDomain · ShipDomain           │
│  Persistiert über alle Szenenwechsel hinweg                         │
└───────────┬─────────────────┬─────────────────┬─────────────────────┘
            │                 │                 │
            ▼                 ▼                 ▼
   ┌────────────────┐ ┌────────────────┐ ┌────────────────┐
   │   LAYER 1      │ │   LAYER 2      │ │   LAYER 3      │
   │   OVERWORLD    │ │   BATTLE       │ │   CONQUEST     │
   │   Szene        │ │   CUTSCENE     │ │   SZENE        │
   │                │ │                │ │                │
   │ 960×540 Map    │ │ Zuschauer-     │ │ Tower-Defense  │
   │ Pan/Zoom       │ │ Perspective    │ │ Waves+Towers   │
   │ Worker-Mgmt    │ │ Route-Movement │ │ Ship-as-Minion │
   │ Forschung      │ │ Ship-VS-Ship   │ │ Aktive Verteid.│
   │ Schiffbau      │ │ Pathfinding    │ │ Belohnung      │
   │ Ressourcen     │ │ = Taktik       │ │                │
   └───────┬────────┘ └───────┬────────┘ └───────┬────────┘
           │                  │                  │
           │    RESULT        │   RESULT         │   RESULT
           │  ◄───────────────┤ ◄────────────────┤ ◄──────────────
           │                  │                  │
           ▼                  ▼                  ▼
   ┌──────────────────────────────────────────────────────────────┐
   │              GAME STATE UPDATE                               │
   │  • Ownership (set_faction)  • Worker-Überlebende            │
   │  • Ressourcen-Belohnung    • Victory-Check                  │
   └──────────────────────────────────────────────────────────────┘
```

### Kernregeln

1. **Jede Layer ist eine eigenständige `.tscn`-Szene** mit eigenem GameLoop
2. **`GameState` bleibt Autoload** — persistiert über Szenenwechsel
3. **Szenenwechsel** via `SceneDirector.transition()` → `get_tree().change_scene_to_packed()`
4. **Jede Szene bootstrapped sich neu aus `GameState`**
5. **Ergebnisse werden VOR dem Szenenwechsel in `GameState` geschrieben**

---

## 3. Layer 1 — Strategische Overworld (existiert, erweitern)

### 3.1 Was schon existiert
- `starfield_background.tscn` mit PlanetField, Navigation, Economy, Scouts, ShipBuilder
- `GameState` als Autoload mit 4 Domänen
- Einfacher `Planet.resolve_arrival()` als Legacy-Fallback

### 3.2 Was fehlt

| Fehlendes | Beschreibung |
|---|---|
| **Victory-Check** | Keine Siegbedingung. Muss nach jedem `faction_changed` geprüft werden |
| **Scene-Trigger** | Kein Mechanismus um Layer 2/3 Szenen zu starten |
| **Rückkehr-Protokoll** | Überlebende aus L2/L3 müssen strukturiert zurückkehren |
| **Layer-2/3 Anzeige** | Kein Overlay/Notification wenn Battle/Conquest läuft |
| **Battle-HUD** | Kein "Flottenkampf läuft" Indicator auf der Overworld |

### 3.3 Neue Trigger-Logik

```
ShipBase.arrived → Planet.resolve_ship_arrival()
  → Braucht Battle? (feindliche Flotte am Ziel ODER Pfadüberlappung)
    → JA → GameState.save_battle_context(fleets, route, seed)
          → SceneDirector.transition_to_layer2(battle_context)
    → NEIN → Normaler Resolve (colony/cargo/friendly)
```

---

## 4. Layer 2 — Battle Cutscene (NEU: Pfadbasierte Raumschlacht)

### 4.1 Kernkonzept

**Layer 2 ist ein generierter Cutscene aus der Zuschauerperspektive.** Die Taktik entsteht aus den Flugrouten: Wo sich feindliche Flotten auf dem Waypoint-Netz überlappen oder am selben Ziel ankommen, entsteht der Kampf.

```
NavigationField: A ──waypoint── B ──waypoint── C
                                  │
                              waypoint
                                  │
                              D ──waypoint── E

Flotte Alpha: A → B → C (Angriff auf C)
Flotte Beta:  E → D → B (Verteidigung, unterwegs zu B)

→ Treffen sich bei B! → Layer 2 startet
```

### 4.2 Datenfluss

```
┌──────────────────────────────────────────────────────────────┐
│              BATTLE CUTSCENE GENERATOR                       │
│                                                              │
│  INPUT:                                                      │
│  • FleetSnapshot A (Loadout, Route, Faction, Speed)          │
│  • FleetSnapshot B (Loadout, Route, Faction, Speed)          │
│  • BattleSeed (deterministisch abgeleitet)                   │
│  • NavigationGraph (Waypoints, Kanten)                       │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ 1. ROUTE-BASED ENGAGEMENT DETECTION                    │  │
│  │    • Pfad A und Pfad B teilen Waypoints?               │  │
│  │    • Oder: Pfad A und Pfad B überlappen bei Ankunft?   │  │
│  │    → Engagement-Point berechnen                        │  │
│  │    → Zeitpunkt berechnen (basierend auf Speed)         │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ 2. MOVEMENT SIMULATION                                 │  │
│  │    • Beide Flotten bewegen sich gleichzeitig           │  │
│  │    • Positionen pro Tick entlang ihrer Route           │  │
│  │    • Waffenreichweite = Engagement-Trigger             │  │
│  │    • Pfadsegmente bestimmen Taktik:                    │  │
│  │      - Enger Waypoint = Clustering = AoE-Gefahr       │  │
│  │      - Weiter Pfad = Entfaltung = Flankenmanöver      │  │
│  │      - Gleichzeitig am Ziel = Frontalzusammenstoß     │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ 3. TACTICAL RESOLVE                                    │  │
│  │    • Jedes Schiff: HP, DPS, Range, Speed (aus Traits)  │  │
│  │    • Zielwahl: Nächstes feindliches Schiff in Range    │  │
│  │    • Schaden = DPS × Tick × RNG(seed)                  │  │
│  │    • Bei 0 HP → Zerstört (visual explosion)            │  │
│  │    • Wenn eine Seite 0 Schiffe → Ende                  │  │
│  │    • Max-Ticks als Timeout                             │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  OUTPUT:                                                     │
│  • BattleCutscene (Events + Routes + Positions)              │
│  • BattleResult (winner, survivors_a, survivors_b)           │
└──────────────────────────────────────────────────────────────┘
```

### 4.3 BattleCutscene — Das neue Datenmodell

```gdscript
class_name BattleCutscene
extends Resource

## Enthält die vollständige choreographierte Raumschlacht,
## inklusive Routen, Positionen und Events.

@export var battle_seed: int = 0
@export var duration: float = 0.0

## Die Routen beider Flotten (Array von Pfadpunkten)
@export var route_a: Array[Vector2] = []
@export var route_b: Array[Vector2] = []

## Startpositionen (erster Punkt der Route)
@export var spawn_a: Vector2 = Vector2.ZERO
@export var spawn_b: Vector2 = Vector2.ZERO

## Der Ort an dem sich die Flotten treffen (Waypoint oder Pfadkreuzung)
@export var engagement_point: Vector2 = Vector2.ZERO
@export var engagement_time: float = 0.0  ## Wann erreichen sie den Punkt

## Zeitlicher Ablauf der Schlacht (pro Tick)
@export var ticks: Array[BattleTick] = []

## Endergebnis
@export var result: BattleResult

## Flotten-Identität (für Visuals)
@export var fleet_a: FleetSnapshot
@export var fleet_b: FleetSnapshot


class BattleTick:
    extends Resource
    @export var time: float = 0.0
    @export var positions_a: Array[Vector2] = []  ## Position jedes Schiffs A
    @export var positions_b: Array[Vector2] = []  ## Position jedes Schiffs B
    @export var events: Array[BattleEvent] = []   ## Fire/Hit/Destroyed
    @export var phase: StringName = &""  ## "approach", "engage", "climax", "retreat"
```

### 4.4 Die 4 Phasen der Cutscene

```
PHASE 1: APPROACH (0s — engagement_time - 2s)
─────────────────────────────────────────────
  Flotte A: ═══════════════►  (folgt Route A)
  Flotte B: ◄═══════════════  (folgt Route B)
  Kamera:   Panoramablick, zeigt beide Flotten auf dem Map-Netz
  Tone:     Spannungsaufbau,.engine hum

PHASE 2: ENGAGEMENT (engagement_time ± 1s)
─────────────────────────────────────────────
  Flotte A: ════════► ◄══════ Flotte B
                     💥
  Kamera:   Zoom auf Engagement-Point, Schiffe im Detail
  Tone:     Erste Schüsse, Warnungen

PHASE 3: CLIMAX (engagement_time + 1s — 5s)
─────────────────────────────────────────────
  Flotte A: ──●──●     ●──    (einige zerstört)
  Flotte B:    ●──  ●──●──●   (Positionen verschieben sich)
  Kamera:   Schwenk zwischen Gruppen, Explosionsfokus
  Tone:     Vollgefecht, Detonationen

PHASE 4: RESOLUTION (nach letztem Tick)
─────────────────────────────────────────────
  Überlebende: ════►  (fahren weiter auf Route)
  Kamera:   Weitwinkel, Überlebende ziehen davon
  Tone:     Nachhall, Ergebnis-Panel
```

### 4.5 Pfadbasierte Taktik — Wie Pathfinding die Schlacht bestimmt

```text
Szenario 1: GLEICHER WAYPOINT (Frontalzusammenstoß)
═══════════════════════════════════════════════════
  A ──waypoint X── C    Flotte A: A→X→C (Angriff auf C)
  B ──waypoint X── D    Flotte B: B→X→D (auf dem Weg zu D)
                              │
                         Beide bei X
                              │
                    → Schlacht bei X
                    → Wer zuerst ankommt hat Vorteil (Defensivstellung)

Szenario 2: ÜBERSCHNEIDENDE ROUTEN (Flankenmanöver)
═══════════════════════════════════════════════════
  A ──wp1── wp2── wp3── C    Flotte A: A→C
                  │
              wp4── B         Flotte B: B→wp4→wp2→(andere Route)
                    │
              wp5── D
                    │
  Beide passage bei wp2, aber zu verschiedenen Zeiten
  → Wenn Flotte A wp2 passiert UND Flotte B ist dort → Schlacht
  → Speed Matters: Schnellere Flotte kann entkommen

Szenario 3: GLEICHER ZIELPLANET (Conquest-Trigger)
═══════════════════════════════════════════════════
  A ──route──► Planet Z    Flotte A: Angriff auf Z
  B ──route──► Planet Z    Flotte B: Verteidigung von Z
                              │
                    Beide kommen bei Z an
                              │
                    → Layer 3 (Conquest) wird getriggert
                    → NICHT Layer 2 (kein Flottenkampf, Bodenkampf)

Szenario 4: KEIN ZUSAMMENTREFFEN (kein Battle)
═══════════════════════════════════════════════════
  A ──route──► Planet C    Flotte A: fliegt zu C
  B ──route──► Planet D    Flotte B: fliegt zu D
                              │
                    Verschiedene Ziele, keine Schnittmenge
                              │
                    → Kein Battle → Normaler Resolve am Ziel
```

### 4.6 Engagement-Detection Algorithmus

```gdscript
## Prüft ob zwei Flotten-Routen ein Engagement erzeugen.
## Gibt den Engagement-Point + Zeitpunkt zurück, oder null.

static func detect_engagement(
    route_a: Array[Vector2], speed_a: float,
    route_b: Array[Vector2], speed_b: float
) -> Dictionary:
    # 1. Prüfe ob die Routen geteilte Punkte haben (gleicher Waypoint)
    var shared_points := _find_shared_route_points(route_a, route_b)
    if not shared_points.is_empty():
        # Nächster geteilter Punkt = Engagement-Point
        var engagement := shared_points[0]  ##closest to start
        var time_a := _time_to_point(route_a, speed_a, engagement)
        var time_b := _time_to_point(route_b, speed_b, engagement)
        return {
            "point": engagement,
            "time_a": time_a,
            "time_b": time_b,
            "type": &"waypoint_convergence"
        }

    # 2. Prüfe ob sich die Routen schneiden (Pfadkreuzung)
    var crossing := _find_route_crossing(route_a, route_b)
    if crossing != Vector2.ZERO:
        var time_a := _time_to_point(route_a, speed_a, crossing)
        var time_b := _time_to_point(route_b, speed_b, crossing)
        # Nur wenn innerhalb ±2s — sonst verfehlen sie sich
        if absf(time_a - time_b) < 2.0:
            return {
                "point": crossing,
                "time_a": time_a,
                "time_b": time_b,
                "type": &"path_crossing"
            }

    # 3. Prüfe ob sie am selben Ziel ankommen (Conquest-Trigger)
    var dest_a := route_a[route_a.size() - 1]
    var dest_b := route_b[route_b.size() - 1]
    if dest_a.distance_to(dest_b) < 5.0:
        return {
            "point": dest_a,
            "time_a": _time_to_point(route_a, speed_a, dest_a),
            "time_b": _time_to_point(route_b, speed_b, dest_b),
            "type": &"destination_arrival"
        }

    return {}  ## Kein Engagement
```

### 4.7 Cutscene Rendering (BattleCinematicScene)

```
BattleCinematicScene.tscn
├── CanvasLayer (90)  ← über allem
│   ├── Control (RootControl, full rect)
│   │   ├── ColorRect (Background, dunkelblau, 92% opacity)
│   │   ├── Node2D (Arena)  ← hier passiert alles
│   │   │   ├── Node2D (RouteLines)  ← Pfadlinien beider Flotten
│   │   │   ├── CompositeShipView (Ship_A_0)  ← pro Schiff
│   │   │   ├── CompositeShipView (Ship_A_1)
│   │   │   ├── CompositeShipView (Ship_B_0)
│   │   │   ├── Line2D (WeaponFire)  ← Schusslinien
│   │   │   ├── Node2D (Explosions)  ← Zerstörungs-Animationen
│   │   │   └── Label (EngagementLabel)  ← "Feindkontakt bei Waypoint X"
│   │   ├── Label (StatusLabel)  ← "⚔️ RAUMSCHLACHT — WEGPUNKT OMEGA"
│   │   ├── HBoxContainer (FleetInfo)  ← Stärke beider Flotten
│   │   └── IngamePlayerControls (Play/Pause/Speed/Skip)
│   └── Control (ResultOverlay)  ← nach Kampfende
│       ├── Label (Winner)
│       ├── VBoxContainer (Survivors)
│       └── Button (Continue)
```

### 4.8 Ship-Visuals im Battle-Cutscene

Jedes Schiff wird als `CompositeShipView` gerendert — identisch zum Hangar:
- Hull-Textur (hull_t1_scout, hull_t2_destroyer, etc.)
- Drive-, Weapon-, Shield-, Scanner-Overlays
- Faction-Tint (Blau für Alpha, Rot für Beta)
- Variants aus dem seed-deterministischen Pool

Die Schiffe bewegen sich pro Tick entlang ihrer Route:
```
Tick 0:  Ship_A_0 bei route_a[0]    Ship_B_0 bei route_b[0]
Tick 1:  Ship_A_0 bei route_a[1]    Ship_B_0 bei route_b[1]
Tick 2:  Ship_A_0 bei route_a[1.5]  Ship_B_0 bei route_b[1.5]  ← IM RANGE
         → FIRE Event → Schusslinie A→B
Tick 3:  Ship_A_0 HP: 85/100       Ship_B_0 HP: 72/100
         → HIT Event → Flash + FloatingText "-15"
...
Tick N:  Ship_A_0 HP: 0 → DESTROYED → Explosion
         Ship_B_0 HP: 45/100 → Überlebend
```

### 4.9 Kamera-System

```
Phase 1 (Approach):
  Kamera-Ziel: Mittelpunkt zwischen beiden Flotten
  Zoom: 0.4x (weite Ansicht des Map-Netzes)
  Bewegung: Langsamer Pan von Flotte A zu Flotte B

Phase 2 (Engagement):
  Kamera-Ziel: Engagement-Point
  Zoom: 0.8x (Schiffe werden sichtbar)
  Bewegung: Zoom-in mitTween

Phase 3 (Climax):
  Kamera-Ziel: Wechselt zwischen aktivsten Kämpfen
  Zoom: 1.0x (Nahkampf-Ansicht)
  Bewegung: Schwenk zu Ship mit niedrigsten HP

Phase 4 (Resolution):
  Kamera-Ziel: Überlebende Flotte
  Zoom: 0.6x (Weitwinkel, Abzug)
  Bewegung: Folgt Überlebenden auf ihrer Route
```

---

## 5. Layer 3 — Conquest Szene (NEU: Tower-Defense)

### 5.1 Kernkonzept

Layer 3 wird getriggert wenn eine militärische Flotte am Zielplaneten ankommt und dort feindliche Verteidigung vorfindet. Es ist ein eigenständiges Tower-Defense-Spiel auf dem Planeten.

```
Trigger: ShipBase.arrived → Militär-Flotte vs. Planet-Verteidigung
→ SceneDirector.transition_to_layer3(conquest_context)
→ Layer 3 Szene bootet
```

### 5.2 Ship-as-Minion-Adapter

```
ShipLoadout (aus dem ShipBuilder)
  ├─ hull_id     → Minion HP (hull HP + shield HP)
  ├─ weapon_id   → Minion DPS (weapon DPS + module DPS)
  ├─ drive_id    → Minion Speed (movement speed auf dem Planeten)
  ├─ shield_id   → Minion Armor (Schadensreduktion)
  └─ module_ids  → Minion Abilities (z.B. AoE, Healing)

→ AssaultMinion:
  HP: 50 + hull.tier*30 + shield.tier*20 + shield_trait.hull_hp_bonus
  DPS: 10 + weapon.tier*5 + module.tier*5 + weapon_trait.dps_bonus
  Speed: 80 * drive_trait.transfer_speed_multiplier * 0.3
  Range: weapon_trait.attack_range_bonus (Bodenreichweite)
  Visual: Miniatur-CompositeShipView (Scale 0.15)
```

### 5.3 Tower-System

```gdscript
class_name DefenseTower
extends Node2D

## Erzeugt aus PlanetUpgradeDefinition:
## - defense_grid → Grund-Turm
## - orbital_station → Flugabwehr
## - weapon_lab → Schwerer Turm
## - armor_lab → Schild-Turm

var tower_def: DefenseTowerDefinition
var range: float = 150.0
var dps: float = 5.0
var fire_interval: float = 1.0
var target_tags: Array[StringName] = [&"minion"]
var level: int = 1

func _process(delta: float) -> void:
    # Turm schießt auf nächsten Minion in Range
    _fire_at_nearest_target()

func _fire_at_nearest_target() -> void:
    var nearest := _find_nearest_minion()
    if nearest != null and _can_fire():
        nearest.take_damage(dps)
        _spawn_laser_effect(global_position, nearest.global_position)
```

### 5.4 Wave-System

```
WAVE STRUCTURE:
═══════════════
Wave 1: 3× Basis-Minion (Leicht bewaffnet)
Wave 2: 5× Basis-Minion + 1× Schwerer Minion
Wave 3: 8× Basis-Minion + 2× Schwerer + 1× Schneller
...

SPAWN PUNKT: Links vom Planeten (Rand des Arenas)
ZIEL: Planet-Mitte (wenn Minion ankommt → HP-Verlust)
TÜRME: Orbitieren den Planeten (von perimeter_slots bestimmt)
GARNISON: Workers auf dem Planeten (kämpfen automatisch)
```

### 5.5 Conquest-Szene Aufbau

```
ConquestScene.tscn
├── CanvasLayer (90)
│   ├── Control (RootControl, full rect)
│   │   ├── ColorRect (Background, dunkelgrün-braun)
│   │   ├── Node2D (Arena)  ← Zentriert auf Planet
│   │   │   ├── Sprite2D (PlanetCore)  ← Der angegriffene Planet
│   │   │   ├── Node2D (Towers)  ← Defense Towers
│   │   │   │   ├── DefenseTower (Tower_0)  ← Orbitiert
│   │   │   │   ├── DefenseTower (Tower_1)
│   │   │   │   └── DefenseTower (Tower_2)
│   │   │   ├── Node2D (Minions)  ← Angreifende Minions
│   │   │   │   ├── AssaultMinion (Minion_0)
│   │   │   │   ├── AssaultMinion (Minion_1)
│   │   │   │   └── ...
│   │   │   ├── Node2D (Garrison)  ← Verteidigende Worker
│   │   │   └── Node2D (Effects)  ← Laser, Explosionen
│   │   ├── Label (StatusLabel)  ← "⚔️ INVASION — Planet Desert"
│   │   ├── HBoxContainer (WaveInfo)  ← "Wave 2/5"
│   │   ├── ProgressBar (PlanetHP)  ← Planet-Lebenspunkte
│   │   └── IngamePlayerControls
│   └── Control (ResultOverlay)
│       ├── Label (Outcome: "Verteidigt" / "Erobert!")
│       ├── VBoxContainer (Verluste/Überlebende)
│       └── Button (Continue)
```

---

## 6. Szene-Transitions-Protokoll

### 6.1 SceneDirector Erweiterung

```gdscript
## Der aktuelle SceneDirector ist ein CanvasLayer mit Fade-Transition.
## Er muss zum echten SceneTree-Wechsler werden.

class_name SceneDirector
extends CanvasLayer

# NEU: Szenen-Kontext
var _pending_context: Dictionary = {}
var _return_scene: String = ""  ## Zurückkehrende Szene

func transition_to_layer2(battle_context: Dictionary) -> void:
    _pending_context = battle_context
    _return_scene = "res://scenes/backgrounds/starfield_background.tscn"
    transition(0.6, func():
        get_tree().change_scene_to_packed(LAYER2_SCENE)
    )

func transition_to_layer3(conquest_context: Dictionary) -> void:
    _pending_context = conquest_context
    _return_scene = "res://scenes/backgrounds/starfield_background.tscn"
    transition(0.6, func():
        get_tree().change_scene_to_packed(LAYER3_SCENE)
    )

func transition_to_layer1() -> void:
    _pending_context = {}
    transition(0.6, func():
        get_tree().change_scene_to_packed(LAYER1_SCENE)
    )

func get_pending_context() -> Dictionary:
    var ctx := _pending_context
    _pending_context = {}
    return ctx
```

### 6.2 Vollständiger Ablauf

```
[OVERWORLD] ShipBase.fliegtRoute entlang
    │
    ▼
[OVERWORLD] ShipBase.arrived feuert
    │
    ▼
[OVERWORLD] PlanetArrivalResolver.resolve_ship_arrival()
    │ Braucht Battle? (feindliche Flotte am Ziel)
    ├── JA → FleetBattleSimulator.simulate_battle()
    │        → CombatReplay generiert
    │        → conflict_simulated.emit(&"battle", replay)
    │        → ConflictManager._start_replay()
    │        → SceneDirector.transition_to_layer2(context)
    │           → Fade-Out Overworld
    │           → SceneTree wechselt zu BattleCinematicScene
    │           → BattleCinematicScene liest Context aus GameState
    │           → Cutscene läuft (Route → Engagement → Kampf)
    │           → "Continue" Button
    │           → GameState.apply_battle_result(result)
    │           → SceneDirector.transition_to_layer1()
    │              → Fade-Out Battle
    │              → SceneTree wechselt zu Overworld
    │              → Overworld bootstrapped sich neu aus GameState
    │              → Überlebende Worker auf Heimatplaneten
    │
    ├── COLONY → Planet.set_faction() + register_workers()
    │            → Kein Scene-Wechsel
    │
    └── NEIN (kein Battle nötig)
         → Normaler Resolve
```

### 6.3 Was bei Szenenwechsel passiert

```
VORHER (Overworld):
  • GameState enthält: Ownership, Ressourcen, Forschung, Ships, Upgrades
  • SceneTree: Background + PlanetField + UI
  • Aktive ShipBase-Transits: werden angehalten/freigegeben

SCHritt 1: GameState sichern
  • BattleContext wird in GameState._pending_battle gespeichert
  • Enthält: FleetSnapshots, Routes, Seed, Engagement-Point

SCHritt 2: Szene wechseln
  • get_tree().change_scene_to_packed(BATTLE_SCENE)
  • Overworld-Node-Instanzen werden zerstört
  • GameState (Autoload) bleibt erhalten!

SCHritt 3: Neue Szene bootstrappen
  • BattleCinematicScene._ready()
  → liest GameState._pending_battle
  → erzeugt CompositeShipViews für jedes Schiff
  → startet Cutscene-Playback

SCHritt 4: Ergebnis anwenden
  • Spieler drückt "Continue"
  → GameState.apply_battle_result(result)
    → Überlebende kehren als Worker zurück
    → Ressourcen-Belohnung
    → faction_changed (wenn Eroberung)
  → SceneDirector.transition_to_layer1()

SCHritt 5: Overworld neu bootstrappen
  • StarfieldBackground._enter_tree()
  → Liest ScenarioCatalog
  → Generiert Katalog aus aktivem Seed
  → SeededLayout erzeugt Planeten aus GameState-Ownership
  → Everything reconnectet sich
```

---

## 7. Victory-System

### 7.1 Siegbedingungen

```gdscript
class_name VictoryCondition
extends Resource

enum Type {
    HOMEWORLD_CAPTURE,   ## Gegnerische Homeworld erobert
    DOMINANCE_70,        ## ≥ 70% aller Planeten besessen
    ELIMINATION,         ## Gegner hat 0 Planeten
    DOMINANCE_100,       ## Alle Planeten besessen
}

@export var type: Type = Type.HOMEWORLD_CAPTURE
@export var check_interval: float = 5.0  ## Sekunden zwischen Checks

func check(game_state: Node) -> Dictionary:
    match type:
        Type.HOMEWORLD_CAPTURE:
            # Prüfe ob eine Homeworld die Fraktion gewechselt hat
            ...
        Type.DOMINANCE_70:
            var total := game_state.get_planet_count()
            var owned := game_state.get_ownership_count(faction)
            return {"victory": float(owned) / float(total) >= 0.7}
        Type.ELIMINATION:
            return {"victory": game_state.get_ownership_count(enemy) == 0}
```

### 7.2 Game-Over-Screen

```
GameCycleManager prüft VictoryCondition nach jedem:
  • faction_changed Signal
  • Battle-Result
  • Conquest-Result

Wenn Victory erkannt:
  → PauseMenu wird durch GameOverScreen ersetzt
  → Statistiken: Planeten, Ressourcen, Schiffe gebaut, Kämpfe gewonnen
  → "Neues Spiel" / "Zurück zur Overworld"
```

---

## 8. CPU in Layer 2/3

### 8.1 CPU Battle-Entscheidung

```
CPU schickt Flotte → Overworld
  → ConflictManager erkennt: feindliche Flotte am Ziel
  → Battle nötig

CPU braucht NICHT die Cutscene zu sehen:
  →_skip = true
  → Battle wird sofort simuliert
  → Ergebnis wird direkt angewendet
  → Kein Szenenwechsel für CPU

NUR Spieler-Flotten triggern Layer 2 Cutscene
```

### 8.2 CPU Conquest-Entscheidung

```
CPU greift Planet an → Layer 3
  → ConquestSimulator.simulate_conquest() (deterministisch)
  → _skip = true
  → Ergebnis wird direkt angewendet
  → Kein Szenenwechsel für CPU
```

---

## 9. Fehlende Enden — Zusammenfassung

| # | Fehlend | Layer | Priorität |
|---|---------|-------|-----------|
| 1 | `GameCycleManager` (Victory-Check, Scene-Trigger) | Infra | 🔴 Kritisch |
| 2 | `SceneDirector` → echter SceneTree-Wechsler | Infra | 🔴 Kritisch |
| 3 | `BattleCutscene` Resource (Routen + Ticks) | L2 | 🔴 Kritisch |
| 4 | Route-Basierte Engagement-Detection | L2 | 🔴 Kritisch |
| 5 | `BattleCinematicScene.tscn` | L2 | 🔴 Kritisch |
| 6 | Kamera-System (4 Phasen) | L2 | 🟡 Hoch |
| 7 | `VictoryCondition` System | Infra | 🟡 Hoch |
| 8 | `ConquestScene.tscn` (Tower-Defense) | L3 | 🟡 Hoch |
| 9 | `ShipAsMinionAdapter` | L3 | 🟡 Hoch |
| 10 | Wave-System | L3 | 🟡 Hoch |
| 11 | `DefenseTower` + Tower-Platzierung | L3 | 🟡 Hoch |
| 12 | Rückkehr-Protokoll (Result → Overworld) | Infra | 🟡 Hoch |
| 13 | Game-Over-Screen | Infra | 🟢 Mittel |
| 14 | CPU-Skip für L2/L3 | L2/L3 | 🟢 Mittel |
| 15 | Battle-HUD auf Overworld | L1 | 🟢 Mittel |

---

## 10. Implementierungsreihenfolge

```
PHASE A: Fundament (GameCycle + Transitions)
  A1. GameCycleManager erstellen (Victory-Check, Trigger)
  A2. SceneDirector erweitern (echter SceneTree-Wechsler)
  A3. BattleCutscene Resource definieren
  A4. Route-Basierte Engagement-Detection

PHASE B: Layer 2 Cutscene
  B1. BattleCinematicScene.tscn bauen
  B2. Route-Movement-System (Schiffe folgen Route pro Tick)
  B3. Tactical Resolve (Schiff vs. Schiff mit Traits)
  B4. Kamera-System (4 Phasen)
  B5. Ship-Visuals (CompositeShipView in Cutscene)

PHASE C: Layer 3 Conquest
  C1. ShipAsMinionAdapter
  C2. DefenseTower + Tower-Platzierung
  C3. Wave-System
  C4. ConquestScene.tscn
  C5. ConquestSimulator erweitern (Towers + Minions)

PHASE D: Integration
  D1. Rückkehr-Protokoll (Result → Overworld)
  D2. CPU-Skip für L2/L3
  D3. Victory-System
  D4. Game-Over-Screen
  D5. Preflight-Constraints für neue Systeme
```

---

*SnipWar Game Cycle Concept — Stand: August 2026*
