# SnipWar Design Contract

**Stand:** 19. August 2026
**Quelle:** Laufzeitcode, Resources, Szenen und `scripts/preflight.gd`.
**Regel:** Wenn dieses Dokument und der Code voneinander abweichen, gilt der Code. Eine geplante Regel darf hier erst als implementiert erscheinen, wenn sie einen Laufzeitverbraucher und Preflight-Abdeckung besitzt.

## 1. Aktueller Status

SnipWar ist ein strategischer Overworld-Prototyp mit funktionierendem Karten-, Transit-, Ressourcen-, Forschungs-, Upgrade-, Scout- und deterministischem Konfliktkern. Die Phasen 0 bis 7 (EffectDefinition, Trait-Erweiterungen, Planetensignaturen, Raffinerie-Konvertierung, Perimeter-Slots & Reichweite, CompositeShipView, FleetSnapshot, FleetBattleSimulator, ConquestSimulator und Replay-Szenen) sind implementiert und in `scripts/preflight.gd` verifiziert.

Der Startpunkt ist `scenes/backgrounds/starfield_background.tscn`. `GameState` und `EventLog` sind Autoloads. `StarfieldBackground._enter_tree()` wählt das aktive Szenario und konfiguriert GameState, PlanetField und MeteorField, bevor `Bootstrap` den finalen Layout-Seed setzt.

## 2. Aktiver Katalog und Szenarien

Der Standardkatalog enthält exakt zehn Planeten:

- Player-Homeworld: `ocean`, Faction `a`
- CPU-Homeworld: `paper`, Faction `b`
- acht neutrale Planeten: `ember`, `ice`, `violet`, `desert`, `toxic`, `storm`, `volcanic`, `golden`

Interne Faction-IDs sind `a`, `b` und `neutral`; die semantischen Namen Player/CPU werden nur in UI und Meldungen verwendet.

Es gibt zwei Szenarien:

- `default`: 960×540, zwei XL-Profile, ein L-Profil, sieben variable Profile, freie Zielauswahl (`all_planets`), zufälliger Laufzeit-Seed.
- `wide` / Frontier Ring: 1920×1080, fester Map-Seed, `neighbors_only`, größere Spalten-/Padding-Werte.

Das Szenario wird vor dem Laufzeit-Eintritt von `PlanetField` gewählt. Ein laufender Wechsel des Szenariokatalogs ist kein unterstützter Vertrag.

`WorldConfig` und `PlanetField` bleiben im lokalen Ursprung. Die Layout-Bounds sind in lokalem Raum authored; ein Szenenoffset würde Navigation, Meteore und Planeten verschieben.

## 3. Layout, Details und Navigation

`SeededLayout` erzeugt Katalogplaneten als Laufzeitinstanzen, weist nach dem finalen Seed Größenprofile und Detail-Seeds zu und invalidiert danach Navigation und Nachbarschaftscache.

Größenprofile:

| Profil | Spawnintervall | Spawnmenge | Start-Worker | Bauplätze | Ressourcenbasis |
|---|---:|---:|---:|---:|---:|
| variable | 10 s | 1 | 2 | 1 | 1 |
| L | 7 s | 2 | 4 | 2 | 2 |
| XL | 5 s | 3 | 6 | 3 | 3 |

Worker-Spawning ist am Start deaktiviert. Die Timer existieren, bleiben aber gestoppt, bis eine Worker-Fabrik gebaut wird.

PlanetDetails sind seed-basiert und zählen logische Detailtypen. Das Standardprofil und das Toxic-Profil validieren sich separat; Toxic garantiert Satellit und Asteroidengürtel und kann einen Kometen enthalten. Bewegungsprofile sind pro Detail `full`, `throttled` oder `static`.

Navigation erzeugt genau einen Moon-/Comet-Waypoint pro Layout-Nachbarschaftskante. `NavigationField.find_route()` liefert den gemeinsamen Pfad für Preview und Transit. Das Standardrouting erlaubt jedes Ziel, routet aber trotzdem über dieses Graphnetz; `wide` beschränkt die Zielliste auf Nachbarn.

## 4. GameState als autoritative Quelle

`GameState` besitzt:

- Ownership/Factions und Homeworlds
- Worker-Startwerte
- Planetressourcen-Zuordnung
- Planet-Upgrades
- globale und planetare Forschung
- Discovery- und Scan-Intel
- Worker-Factories und Gathering-Zustand
- Faction-Vaults
- Ship-Part-Inventare und Ship-Assemblies

Planeten spiegeln Faction-Änderungen über `faction_changed`. Ein Capture darf nicht durch direkte Planet-zu-Planet-Ownership-Logik erfolgen.

`reset_from_catalog()` leert Upgrades, Vaults, Forschung, Intel, Gathering und Ship-Builder-Zustand. PlanetDetails entfernt daraufhin Upgrade-Strukturen.

## 5. Ressourcen und Wirtschaft

Der Default-`ResourcePool` enthält fünf unsichtbare Datenobjekte:

- `energy`
- `biomass`
- `rare`
- `volatile`
- `material`

`Bootstrap` dealt die Ressourcen nach dem finalen Layout-Seed seed-deterministisch über den aktiven Katalog. Homeworlds erhalten unterschiedliche Ressourcen; die übrigen Planeten werden round-robin ausgeglichen, sodass die Häufigkeiten höchstens um eins abweichen. Maps können optional einen eigenen `MapDefinition.resource_pool` referenzieren; fehlt er, greift der globale Default-Pool.

Es gibt aktuell **keine** feste Planetentyp→Ressource-Regel. `signature_resource_for_planet_type()` ist eine vorhandene Hilfsmethode, aber die tatsächliche Deal- und Produktionslogik verwendet `resource_of(planet_id)`.

Wirtschaft:

- Der passive Economy-Timer läuft alle 10 Sekunden.
- Er bleibt deaktiviert, bis eine Fraktion `worker_automation` erforscht hat.
- Ein separater Gather-Timer läuft ebenfalls alle 10 Sekunden.
- `collect` registriert persistente Gatherer auf bekannten neutralen Planeten; es gibt keine einmalige Sammelauszahlung.
- Jeder Gather-Tick zahlt `workers × resource_base` in den Vault der sammelnden Fraktion.
- Planetproduktion verwendet `PlanetSizeProfile.resource_base`, Upgrade-`production_boost` und planetare `production_multiplier`-Technologien.
- Maintenance wird best-effort versucht. Fehlende Ressourcen verhindern die jeweilige Maintenance, aber nicht die Produktionsgutschrift.
- `spend_faction_resource()` erlaubt keinen Overdraft und keine Teilzahlung.

## 6. Planet-Upgrades und Traits

Der Default-Katalog enthält 13 `PlanetUpgradeDefinition`-Einträge in vier Zweigen:

- Economy: `extractor`, `refinery`, `trade_post`
- Military: `shipyard`, `war_shipyard`, `colony_shipyard`, `defense_grid`
- Tech: `tech_center`, `weapon_lab`, `armor_lab`
- Infrastructure: `orbital_station`, `colony_hub`, `trade_network`

Implementiert sind:

- Parent-Prerequisites
- gegenseitige Exklusivität
- Ressourcen- und Worker-Kosten
- Technologie-Gates, wo ein Upgrade sie referenziert
- sichtbare `UpgradeStructure_<id>`-Kinder in `PlanetDetails`
- Trait-Verbraucher für `production_boost`, `worker_spawn_bonus`, `defense_rating`, `transfer_speed_multiplier`, `cluster_tier_bonus` und Maintenance

Wichtige Grenzen des aktuellen Vertrags:

- `refinery` konvertiert noch keine Ressource in Rare; sie erhöht nur Produktion und versucht Maintenance.
- `trade_post` und ähnliche Geschwindigkeitsboni sind generische Transfer-Speed-Modifikatoren; es gibt noch kein separates Frachter-Subsystem.
- `cluster_tier_bonus` verändert nur die sichtbare Clusterstufe, nicht logische Kapazität, Packung, Fluglast oder Ankunftsmenge.
- `perimeter_slots_bonus` und `range_bonus` sind Datenfelder ohne vollständige Laufzeitverbraucher für Türme, Garnisonsplätze oder Sichtreichweite.
- `weapon_lab` und `armor_lab` erzeugen noch keinen allgemeinen Transformer-Pool für Mechs oder Schiffe.
- Asset-Komposition existiert für Planet-Upgrade-Strukturen, aber noch nicht als allgemeiner Objekt×Transformer-Child-Pool.

## 7. Forschung, Discovery und Scouts

Der Default-TechnologyCatalog enthält:

- Ship-Technologien: `shipyard_construction`, `scout_hull`, `scanner_drone`, `worker_automation`
- Mech-Technologie: `mech_frame` — sichtbar, aber bis Layer 3 inert
- Planet-Technologien: `planetary_survey`, `planetary_extraction`

Globale Forschung liegt pro Fraktion vor. Planetare Forschung liegt pro Planet vor und darf nur auf einem eigenen bekannten Planeten stattfinden. Planetare Forschung beeinflusst aktuell die Produktionsmultiplikation.

Ein Scout benötigt:

- eigenen Planeten
- Upgrade `shipyard`
- `scout_hull` und `scanner_drone`
- Baukosten
- freien Bauplatz
- unbekannten Layout-Nachbarn als Ziel

`ScoutShip` fliegt `NavigationField.find_route()`, scannt bei Ankunft Ressourcen-ID, Größen-ID und Bauplätze und wird anschließend freigegeben.

## 8. Ship Builder: aktueller Umfang

`ShipPartCatalog` enthält die Slottypen Hull, Scanner und Module sowie zwei maximale Modulplätze. Der Default-Katalog enthält zwei Hüllen, einen Scanner und drei Module.

Kaufen, Montieren und Zerlegen sind in `GameState`, `ShipManager` und `TechnologyMenu` implementiert. Eine Assembly besteht aktuell aus:

```text
hull + scanner + module_ids
```

Assemblies sind Inventar-/Display-Zustand. Sie werden nicht als Dispatch-Fleet, Kampfeinheit oder Scout verwendet. Der einzige aktiv fliegende Schiffstyp ist `ScoutShip`.

## 9. Missionen, Transit und Conflict Resolve

`WorkerManager` unterstützt:

- `military`: nutzt den einfachen militärischen Arrival-Resolve
- `colony`: besiedelt ausschließlich neutrale Planeten friedlich
- `cargo`: verstärkt ausschließlich eigene Planeten
- `collect`: registriert Gatherer ausschließlich auf bekannten neutralen Scan-Zielen

Transit:

- Largest-first-Packing verwendet logische Kapazitäten K=1, M=5 und L=100.
- Sieben Worker werden daher `M + K + K`.
- Alle Gruppen starten im selben Frame.
- Die Formation ist deterministisch und bleibt entlang des Pfades stabil.
- Transitgruppen tragen `source_faction`, `source_planet_id` und `mission_type`.
- Ruhende Worker werden nicht als Sprites gezeichnet, sondern bleiben Planetenzähler.
- Die drei Tier-Definitionen besitzen absichtlich getrennte Kapazitäts- und Displaygrenzen; dadurch kann ein kleiner logischer Load ein größeres sichtbares Tier erhalten.

Default-Flugzeit:

```text
(distance / 100) × 8 × (1 + 0.05 × sqrt(max(unit_count − 1, 0)))
÷ source_transfer_speed_multiplier
```

Preview und tatsächlicher Transit verwenden dieselbe `FlightTime.seconds_for()`-Logik und den Speed-Multiplikator der Quelle.

Militärischer Resolve in `Planet.resolve_arrival()`:

1. gleiche Faction: alle eingehenden Worker verstärken den Zielplaneten;
2. `incoming <= worker_count + defense_rating`: Angriff wird abgewehrt, bis zu `incoming` vorhandene Worker werden entfernt;
3. `incoming > defenders`: Ziel-Faction wechselt über `GameState.set_faction()`, Verteidiger-Worker werden entfernt, Überlebende `incoming - defenders` bleiben am Ziel.

Das ist kein Waffen-, Schadens-, Tower- oder Gefechtssystem. Es gibt keine Layer-2-Simulation und keine aktive Layer-3-Szene.

## 10. CPU und Laufzeit-Timer

`CpuDispatchAI` besitzt standardmäßig einen 12-Sekunden-Entscheidungstimer, zwei Reserve-Worker, mindestens drei Quell-Worker und einen Dispatch-Anteil von 0.5. Die Priorität lautet:

1. nächster neutraler Planet → `colony`
2. schwächerer eigener Planet → `cargo`
3. gegnerischer Planet → `military`

Die AI läuft als Overworld-Dispatcher; sie simuliert keine Schiffs- oder Mech-Kämpfe.

`PlanetEconomyManager` stellt getrennte Hooks für `tick_now()`, `gather_now()`, `set_enabled()` und `set_gathering_enabled()` bereit. Die Preflight-Suite deaktiviert die automatischen Module nach dem Boot und ruft deterministische Test-Hooks manuell auf.

## 11. UI, EventLog und Pause

- `PlanetNetwork` besitzt Routing, Linien und den dynamischen UI-Aufbau.
- `PlanetNetworkUI` läuft auf CanvasLayer 50 und delegiert an `VaultBar` und `PlanetPanel`.
- `TechnologyMenu` läuft auf CanvasLayer 60 und schließt das Planet-Panel bei Öffnung.
- `PauseMenu` läuft auf CanvasLayer 70 und verarbeitet ESC in `PROCESS_MODE_ALWAYS`; bei offenem Planet- oder Technology-Panel pausiert ESC nicht.
- Das Panel berechnet seine effektive Mindestbreite nach dynamischen Listen neu; die Ressourcenleiste wird daneben platziert.
- `EventLog.push()` schreibt einen sichtbaren Toast-Eintrag, `log_silent()` nur Historie.
- MessageFeed zeigt nur sichtbare Einträge und begrenzt die Toast-Anzahl.
- `EventLog` exportiert standardmäßig erst bei `NOTIFICATION_WM_CLOSE_REQUEST` nach `user://player.log`; Headless-Läufe schreiben nicht automatisch den echten Spielerlog.

## 12. Präsentation und Rendering

`Background` liegt auf z=-100, `PlanetField` auf z=20. Starfield-Sterne und Staub nutzen `MultiMeshInstance2D`; Folds und Grain werden über `draw_multiline()` mit konfigurierbaren Alpha-Buckets gezeichnet. Viewport-Resizes bauen die Batches neu auf.

Die Zielpräsentation ist 4K-fähig gedacht, aber der verifizierte technische MVP bleibt 960×540 mit Canvas-Item-Stretch und einem 1280×720-Fenster-Override.

## 13. Nicht Bestandteil dieses Contracts

Folgende Aussagen sind derzeit Zukunftsplanung und dürfen nicht als implementierte Features behandelt werden:

- Isaac-artiger Ship-Item-Pool mit multiplikativen Loadout-Interaktionen
- allgemeiner Objekt-/Transformer-/Trait-Child-Pool für alle Domänen
- echte Ship-Fleet-Snapshots und mehrere einsatzfähige Schiffsklassen
- Layer-2-Flottensimulation, Schiff-KI und animierte Raumkampf-Cutscene
- Tower-Defense, Türme, aktive Garnisonsverteilung und Layer-3-Eroberung
- Ship-as-Minion-Adapter und Mech-Kampflogik
- Planetentypen als echte Ressourcen-Signaturen
- Ressourcenkonvertierung, Siegbedingungen und Kampagnenzustand

## 14. Verifikation

Die zentrale Regression-Suite ist `scripts/preflight.gd`. Sie deckt unter anderem Scene-Boot, Kataloge, Ressourcen-Deal, Seed-Variation, Größenprofile, Details, Navigation, UI, Upgrades, Missionen, CPU-Hooks, Scouts, Ship-Builder, EventLog, Kontextmenü und Pause-Verhalten ab.

Ein separater Main-Scene-Smoke-Test ist:

```text
godot --headless --path . --quit-after 2
```

Die Suite wurde mit Godot 4.7.2 aus dem bereitgestellten lokalen Binary ausgeführt und meldete `PASS: SnipWar preflight`; auch der Main-Scene-Smoke-Test mit `--quit-after 2` war erfolgreich. Die Aussagen oben wurden aus Code, Resources, den vorhandenen Preflight-Assertions und diesem Lauf abgeleitet.

## 15. Feature-Matrix

**Statusbegriffe:**

- **Implementiert:** Laufzeitpfad vorhanden und durch Preflight oder den verifizierten Smoke-Test abgedeckt.
- **Teilweise:** Ein nutzbarer Slice existiert, aber der beschriebene Zielumfang oder ein geplanter Verbraucher fehlt.
- **Geplant:** Noch kein autoritativer Laufzeitpfad und keine Preflight-Abdeckung.

| Bereich | Feature | Status | Code-/Resource-Grenze |
|---|---|---|---|
| Fundament | Szenarioauswahl, zehn Katalogplaneten, zwei Homeworlds, acht neutrale Welten | Implementiert | `starfield_background.gd`, `scenario_catalog.tres`, `planet_catalog.tres` |
| Fundament | Seed-Layout, Größenprofile, Startgarnisonen und Bauplätze | Implementiert | `seeded_layout.gd`, `planet_size_profile.gd` |
| Präsentation | PlanetDetails, Toxic-Garantien, Fidelity-Profile, Meteore, Starfield-Batches | Implementiert | `planet_details.gd`, `starfield_background.gd`, `preflight.gd` |
| Navigation | Nachbarschaftsgraph, Waypoints, Routen, `all_planets`/`neighbors_only` | Implementiert | `navigation_field.gd`, `planet_network.gd` |
| Besitz | GameState-Ownership, Faction-Signale, Homeworld- und Capture-Zustand | Implementiert | `game_state.gd`, `planet.gd` |
| Ressourcen | Fünf Ressourcen, seed-deterministischer Deal, Homeworld-Differenz, Vaults | Implementiert | `game_state.gd`, `resource_pool_default.tres` |
| Wirtschaft | Passive Produktion, Maintenance, Gather-Timer und persistente Sammeltrupps | Implementiert | `economy_manager.gd`, `game_state.gd`, `planet.gd` |
| Ressourcenmodell | Planetentyp als echte Ressourcen-Signatur | Geplant | Vorhandene Mapping-Hilfsmethode wird nicht vom Deal/Production-Pfad verwendet |
| Wirtschaft | Raffinerie als tatsächliche Ressourcen-Konvertierung | Geplant | `refinery` ist aktuell Produktionsbonus plus Maintenance |
| Upgrades | 13 Upgrades, vier Branches, Kosten, Parent-/Exklusivitätsregeln | Implementiert | `planet_upgrade_catalog_default.tres`, `game_state.gd` |
| Upgrades | Sichtbare Upgrade-Strukturen auf Planeten | Implementiert | `planet_details.gd`, `planet.gd` |
| Traits | Produktion, Spawnrate, Defense-Rating, Transfer-Speed, sichtbarer Tier-Bonus | Implementiert | `trait_definition.gd`, `planet.gd`, Transitpfad |
| Traits | Perimeter-Slots, Reichweite, allgemeiner Objekt×Transformer-Child-Pool | Teilweise | Datenfelder und einzelne Asset-Strukturen existieren; vollständige Verbraucher fehlen |
| Forschung | Globale/planetare Technologien, Prerequisites und Discovery-Gates | Implementiert | `technology_catalog.gd`, `game_state.gd` |
| Scouts | Werft-/Tech-/Kosten-/Nachbar-Gates, Flug, Scan-Intel und Freigabe | Implementiert | `ship_manager.gd`, `scout_ship.gd` |
| Ship Builder | Teile kaufen, montieren, zerlegen und im Hangar visualisieren | Teilweise | Assemblies sind Inventar-/Display-Zustand, keine einsatzfähigen Schiffe |
| Schiffe | Assemblies als aktive Flotten, Loadout-Traits und mehrere Schiffsklassen | Geplant | Nur `ScoutShip` fliegt aktuell |
| Transit | Slider, Flugzeit, K/M/L-Packung, Formation, Ankunfts-Resolve | Implementiert | `worker_manager.gd`, `worker_cluster.gd`, `flight_time.gd` |
| Missionen | Military, Colony, Cargo und Collect mit missionsabhängigen Gates | Implementiert | `planet.gd`, `worker_manager.gd`, `planet_network.gd` |
| CPU | Timer-basierter Colony-/Cargo-/Military-Dispatcher | Implementiert | `cpu_dispatch_ai.gd`, `cpu_dispatch_default.tres` |
| Konflikt | Deterministischer Worker- plus Defense-Rating-Resolve | Implementiert | `Planet.resolve_arrival()` |
| Layer 2 | KI-gesteuerte Flottensimulation mit BattleResult/Event-Stream | Geplant | Keine Battle- oder Fleet-Simulation vorhanden |
| Layer 2 | Animierte Raumschlacht als Replay/Cutscene | Geplant | Keine Battle-Szene vorhanden |
| Layer 3 | Planetare Tower-Defense und aktive Verteidigung | Geplant | Keine Turm-, Wave- oder Conquest-Szene vorhanden |
| Layer 3 | Ship-as-Minion-Adapter mit visueller/logischer Adaption | Geplant | Keine Assault-Minions vorhanden |
| Kampagne | Siegbedingungen, Kampagnenzustand und persistente Konfliktziele | Geplant | Kein Laufzeitmodell vorhanden |
| UI/Tools | Planet-Panel, VaultBar, TechnologyMenu, MessageFeed, PauseMenu, EventLog | Implementiert | `scripts/ui/*`, `planet_network.gd`, `event_log.gd` |

## 16. Umsetzungplan gegen das bestehende Fundament

Dieser Plan ist die Reihenfolge für die zuvor als teilweise oder geplant markierten Systeme. Er erweitert den aktuellen Vertical Slice schrittweise, statt `GameState`, `Planet`, `WorkerManager` und `TransformerConfig` gleichzeitig zu einem untestbaren Universalsystem umzubauen.

### 16.1 Architektur- und Engine-Grenzen

Der Projektstand ist mit Godot **4.7.2 stable** geprüft; Main-Scene-Smoke-Test und `scripts/preflight.gd` laufen erfolgreich. Das Projekt verwendet Godot 4.7 mit GL Compatibility und einer 2D-Node-/Resource-Architektur.

Für die neuen Layer gilt:

- **Persistente Daten:** Custom `Resource`-Klassen, nicht Nodes. Das betrifft Effekte, Objekte, Transformer, Ship-Assemblies, Fleet-Snapshots, Battle-Resultate und Tower-Definitionen.
- **Reine Simulation:** `RefCounted`-Klassen oder statische, typisierte Hilfsklassen ohne SceneTree, Timer, Tween oder `GameState`-Zugriff. Das macht Layer 2/3 headless und deterministisch testbar.
- **Laufzeit-Orchestrierung:** Ein neues `ConflictManager`-Modul wird von `SeededLayout._create_runtime_modules()` erzeugt. Es bleibt ein Laufzeitmodul von `PlanetField` und wird nicht als globaler Autoload eingeführt.
- **Visuals:** Eigene PackedScenes (`ShipVisual`, `BattleScene`, später `ConquestScene`). Sie erhalten Snapshots per Methode und melden Ergebnisse per typisierten Signals nach oben.
- **Keine Physik als Wahrheitsquelle:** Flottenkontakt, Battle-Ticks und Minion-Waves werden aus Fortschritt, Pfad und festen Simulations-Ticks berechnet. Godot-Tweens visualisieren nur einen bereits festgelegten Zustand.
- **Komposition statt Seitwärtszugriff:** `PlanetNetwork` meldet Dispatch-Anfragen; `ConflictManager` führt sie aus. Neue Szenen greifen nicht direkt in fremde Internals oder in `GameState`-Dictionaries ein.
- **Godot-Lifecycle:** Bekannte Szenen werden per `preload()` referenziert, Laufzeitkinder mit `add_child()` erzeugt und mit `queue_free()` entfernt. `@tool` bleibt auf Inspector-/Resource-Validierung beschränkt.
- **Bestehende Verträge bleiben:** `GameState` bleibt SSOT für Ressourcen, Ownership und persistenten Build-Zustand. Workerzahlen und Größenprofile bleiben auf `Planet`; sie werden für Simulationen als Snapshot injiziert.

`TransformerConfig` wird nicht zum universellen Datencontainer umfunktioniert. Es bleibt Präsentationskonfiguration für Tints, Orbitmathematik und UI-nahe Planetdarstellung.

### 16.2 Phasen und Abhängigkeiten

| Phase | Ergebnis | Abhängigkeit | Abnahmekriterium |
|---|---|---|---|
| 0 | Gemeinsame typed Effect-/Object-/Transformer-Verträge | keine | Kataloge validieren; bestehender Preflight bleibt grün |
| 1 | Planetensignaturen und echte Raffinerie-Konvertierung | Phase 0 | Seed-Deal, Produktion, Maintenance und Conversion sind transaktionssicher getestet |
| 2 | Perimeter- und Reichweitenverbraucher | Phase 1 | Profil- und Upgrade-Werte beeinflussen echte Destination-/Defense-Snapshots |
| 3 | Allgemeiner visueller Object×Transformer-Child-Pool | Phase 0 | Planetstruktur und ein Schiff werden aus denselben Kompositionsregeln erzeugt |
| 4 | Aktive Ship-Assemblies und Fleet-Snapshots | Phase 3 | Eine Assembly kann gebaut, gestartet, verloren, zurückgeführt und visualisiert werden |
| 5 | Layer-2-Flottensimulation und Replay-Cutscene | Phase 4 | gleiche Snapshots plus Seed liefern dasselbe Resultat und denselben Event-Stream |
| 6 | Layer-3-Conquest mit Tower Defense und Ship-as-Minion | Phase 2, 4, 5 | Auto-Resolve und aktive Verteidigung verwenden denselben deterministischen Resolver |
| 7 | Integration, Balancing und Performance-Härtung | Phase 1–6 | alter Layer-1-Preflight, neuer Layer-Preflight und Smoke-Test laufen gemeinsam |

Keine spätere Phase darf die nächste vorwegnehmen. Insbesondere werden BattleScene und ConquestScene nicht gebaut, solange Ship-Assemblies keine autoritativen Loadout-Snapshots besitzen.

### 16.3 Phase 0 — gemeinsame Datenverträge

**Neue Datenebene:**

- `TraitEffect`/`EffectBundle`: gemeinsame, typisierte Modifikatoren für Produktion, Transfer, Verteidigung, Angriff, Energie-/Maintenance-Kosten und visuelle Tags.
- `ObjectDefinition`: wiederverwendbare Grundform mit Objekt-ID, Domäne/Slot und Basis-Asset.
- `TransformerDefinition` und `TransformerCatalog`: kompatible Ziel-Slots, visuelle Overlays/Tints und referenzierte Effects.
- `BuildSnapshot`: immutable Laufzeitauflösung aus Objekt, Transformern und Effects.

`TraitDefinition` bleibt zunächst kompatibel für bestehende Planet-Upgrades und wird über einen Adapter in `EffectBundle` aufgelöst. `PlanetUpgradeDefinition`, `ShipPartDefinition` und spätere `MechPartDefinition` bleiben getrennte Domänen-Resources.

**Nicht in Phase 0:** Shader-Deformation, zufällige Asset-Generierung, freie `load()`-Pfade oder eine allwissende Trait-Klasse mit untypisierten Dictionaries.

### 16.4 Phase 1 — Planetensignaturen und Raffinerie

1. `PlanetDefinition` erhält eine explizite `resource_signature_id` statt einer impliziten Namens-Mapping-Regel.
2. `PlanetCatalog.validate()` und `MapDefinition.validate()` prüfen gültige Resource-IDs, Homeworld-Differenz und Pool-Kompatibilität.
3. `GameState.deal_resources()` verwendet authored signatures, behält für ältere Maps aber einen klar definierten seed-deterministischen Fallback.
4. Eine serialisierbare `ResourceConversionDefinition` beschreibt Input, Output, Ratio und optional ein Produktionslimit. `refinery` referenziert diese Definition, statt in `game_state.gd` hartcodiert zu werden.
5. Die Produktion wird als eine atomare Transaktion berechnet: Roh-Ertrag, Maintenance und Conversion werden validiert, dann gemeinsam in den Vault geschrieben. `spend_faction_resource()` bleibt overdraft-sicher.
6. `resource_generated` und EventLog erhalten die tatsächliche Output-Ressource; stille Rohstoff-/Maintenance-Schritte erzeugen keinen Toast.

**Preflight:** feste Signaturen je Planet, Homeworld-Differenz, ausgeglichener Fallback, 1:1-Conversion, fehlende Input-Ressource, Maintenance ohne Partial Spend und Wiederholbarkeit mit gleichem Seed.

### 16.5 Phase 2 — Perimeter und Reichweite

`build_slot_count` bleibt der Bau-/Worker-Slot und wird nicht zum Tower-Slot umgedeutet.

1. `PlanetSizeProfile` oder eine separate `PlanetDefenseConfig` erhält `perimeter_slots_base` und `action_range_base`.
2. `Planet.get_perimeter_slot_count()` addiert Profilbasis und `perimeter_slots_bonus`.
3. `Planet.get_action_range()` addiert Profilbasis und `range_bonus`; die Berechnung verwendet die gemeinsame Navigationspfadlänge, nicht die direkte Luftlinie.
4. `PlanetNetwork` filtert Scout-/Expansionsziele über einen klar benannten Range-Check, ohne den globalen `route_mode` mit Sichtbarkeit zu vermischen.
5. `PlanetDefenseSnapshot` exportiert Worker-Garnison, freie Slots, Defense-Rating und erlaubte Reichweite für spätere Resolver.
6. UI zeigt freie/gesamte Perimeter-Slots und Reichweiten-Intel; der Wert wird nicht nur im Trait-Tooltip angezeigt.

**Preflight:** Profilbasis, Upgradebonus, Range-Grenze auf direkter und mehrteiliger Route, Capture-Reset und keine Verwechslung von Build- und Perimeter-Slots.

### 16.6 Phase 3 — Object×Transformer-Child-Pool

Der erste vertikale Slice ist eine vorhandene Planetstruktur, danach ein Ship-Hull mit einem Modul. Erst wenn beide funktionieren, werden weitere Assets migriert.

1. `PlanetUpgradeDefinition.visual_asset` wird schrittweise durch `ObjectDefinition` plus Transformer-Referenz ergänzt; ein Kompatibilitätsfallback erhält alte Resources.
2. `ObjectVisual` erzeugt bekannte `Sprite2D`-/Overlay-Kinder aus einem Snapshot. Kinder besitzen keine Wirtschaft oder Kampflogik.
3. `PlanetDetails.add_upgrade_structure()` verwendet den Visual-Builder; Orbitradius, Phase und Tints kommen weiterhin aus `TransformerConfig`/Transformer-Definitionen.
4. `ShipyardHangar` erhält denselben Kompositionspfad für Hull, Scanner, Module und Overlay-Assets. `FutureShipBuilder` bleibt als Anzeige kompatibel.
5. Asset-Definitionen werden validiert: keine Null-Assets, kompatible Slots, keine doppelten IDs, deterministische Kindreihenfolge.

**Engine-Regel:** Runtime-Visuals werden als Kinder erzeugt und mit `queue_free()` ersetzt. Da sie nicht serialisiert werden, brauchen sie keinen Editor-Owner; eine echte `@tool`-Vorschau wäre ein späterer, separater Schritt.

### 16.7 Phase 4 — aktive Ship-Assemblies

Die aktuelle Dictionary-Assembly wird in einen typisierten persistenten Zustand überführt, ohne `GameState` zum Scene-Manager zu machen.

1. `ShipAssembly`/`ShipLoadoutSnapshot` enthält ID, Besitzer, Ursprungsplanet, Objekt-/Transformer-IDs, resolved Effects, Status (`hangar`, `transit`, `battle`, `destroyed`) und Mission-Rolle.
2. `ShipPartDefinition` erhält slot-kompatible Effects und Rollenprofile. Die vorhandenen Hull-, Scanner- und Modul-Slots bleiben gültig; Waffen-/Antriebsrollen kommen als neue Module, nicht als Sonderfälle in `ShipManager`.
3. `GameState` erhält atomare Methoden `reserve_ship`, `launch_ship`, `return_ship`, `destroy_ship` und `get_ship_snapshot`. Direkte Dictionary-Manipulation bleibt intern.
4. `ShipManager` bleibt für Kauf, Assembly und Hangar zuständig. Ein neues `ConflictManager` übernimmt Fleet-Auswahl und Start.
5. `FleetTransit` visualisiert eine Liste von Loadout-Snapshots. `WorkerCluster` bleibt der Worker-Transit und wird nicht mit Schiffsstatus überladen.
6. Der erste aktive Slice unterstützt eine kleine Kampf-Flotte aus bereits montierten Assemblies. Der Scout-Scan bleibt separat und behält seine Tech-Gates.

**Preflight:** keine Doppelstarts, Assembly bleibt nach Visual-Free erhalten, Launch sperrt das Inventar, Rückkehr gibt den korrekten Status frei, Verlust entfernt nur die betroffene Assembly und Catalog-Reset räumt aktive Transitvisuals auf.

### 16.8 Phase 5 — Layer 2: Simulation und Cutscene

**Pure Simulation:**

- `FleetBattleSimulator` als `RefCounted`
- `FleetBattleSnapshot`/`ShipCombatSnapshot`
- `BattleContext` mit Seed, fixed tick rate, max ticks und Balance-Config
- `BattleEvent` für Spawn, Target, Hit, Damage, Retreat, Destroyed und Result
- `BattleResult` mit Gewinner, Überlebenden, Verlusten und nächstem Zielzustand
- deterministische `FleetBattleAI` ohne SceneTree-Zugriff

Der Simulator würfelt ausschließlich über einen lokal gesetzten `RandomNumberGenerator.seed` oder eine reproduzierbare Seedable-Funktion. Er mutiert weder `GameState` noch Nodes. Der `ConflictManager` übergibt Snapshots und nimmt das Resultat entgegen.

**Replay:**

- `BattleScene.tscn` kapselt Kamera, Background, `ShipVisual`-Instanzen und Event-Replay.
- `BattleScene.setup(replay_data)` ist die einzige Datenübergabe nach unten.
- `battle_finished(result)` ist das Signal nach oben.
- Die Szene illustriert die Events; sie darf Treffer oder Verluste nicht selbst entscheiden.
- Nach dem Replay committen `ConflictManager`/GameState das Ergebnis genau einmal.

Flottenkontakt wird zunächst über Transitfortschritt, Ziel und Pfadsegmente erkannt, nicht über unvorhersehbare `Area2D`-/Physik-Kollisionen. Eine spätere visuelle Kollisionsdarstellung kann darübergelegt werden.

**Preflight:** gleiche Eingabe erzeugt gleiche Events, Battle endet immer innerhalb `max_ticks`, kein Node-/GameState-Leak während Preview, spätere Gruppen werden nach dem Ergebnis korrekt behandelt, BattleScene meldet exakt einmal.

### 16.9 Phase 6 — Layer 3: Conquest und Ship-as-Minion

1. `DefenseTowerDefinition`, `PlanetDefenseLoadout` und `DefenseTowerSnapshot` bilden Türme mit Slot, Range, Damage, Fire-Interval, Target-Tags und Transformer-Visual.
2. `AssaultMinionDefinition` wird durch einen reinen Adapter aus `ShipLoadoutSnapshot` erzeugt. Hull, Module, Effects und Visual-Komposition bleiben die gemeinsame Quelle; Bodenwerte werden nicht in Ship-Code dupliziert.
3. `ConquestSimulator` verwendet feste Ticks/Waves und erhält `ConquestSnapshot` aus Angreifer-Minions, Verteidigung, Garnison und Planetbonus.
4. `ConquestScene.tscn` stellt bei einem Spieler-Verteidigungsfall Befehle über Signals bereit: Tower-Ziel, Garnisonszuweisung und Wave-Interaktion. Die Szene schreibt nicht selbst in `GameState`.
5. Ein Angriff auf einen Gegner verwendet denselben Simulator mit einer gegnerischen AI-Command-Policy und kann als automatische Conquest-Replay-Sequenz gezeigt werden.
6. `ConquestResult` wird einmalig committed: Besitzwechsel über `GameState.set_faction()`, verbleibende Garnison, verlorene Minions/Schiffe und aktualisierter Ressourcenfluss.
7. `Planet.resolve_arrival()` bleibt als Legacy-/Overworld-Fallback bestehen, bis der neue Conquest-Pfad durch Szenario-Flag und Preflight vollständig ersetzt werden kann.

**Preflight:** Tower-Slotlimit aus `perimeter_slots`, Range- und Target-Regeln, gleiche Inputs/Seeds, aktive Verteidigerbefehle, Auto-Resolve-Parität, Capture-Signal, Ergebnis-Commit genau einmal und Queue-Free aller visuellen Einheiten.

### 16.10 Phase 7 — Integration und Freigabe

- `ScenarioDefinition` erhält zunächst Feature-Flags für `fleet_battles` und `conquest`; `default` bleibt bis zum erfolgreichen Slice auf `false`.
- Jede Phase ergänzt eine neue `_constraint_*()`-Funktion in `preflight.gd`; keine bestehende Constraint wird mit globalem Reset umgangen.
- Die Reihenfolge der Constraints bleibt deterministisch; der gemeinsame `GameState` wird nur an expliziten Übergabepunkten verändert.
- Main-Scene-Smoke-Test, Preflight, `git diff --check` und ein kurzer Runtime-Profiler-Lauf werden vor Aktivierung eines Flags ausgeführt.
- Bei wachsender Anzahl sichtbarer Minions wird erst gemessen; für niedrige Battle-/Conquest-Kontingente bleiben normale Child-Nodes die lesbarere Lösung. Pooling oder `MultiMeshInstance2D` sind Optimierungen, keine Simulationsabhängigkeiten.

### 16.11 Definition of Done

Ein Schritt gilt erst als abgeschlossen, wenn:

1. die Datenverträge typisiert und validiert sind;
2. die Laufzeitregel ohne UI reproduzierbar getestet werden kann;
3. Preview/Replay keine autoritativen Zustände verändert;
4. die Szene nur über Methoden nach unten und Signals nach oben kommuniziert;
5. Godot 4.7.2 Headless-Smoke und Preflight grün bleiben;
6. die Feature-Matrix in Abschnitt 15 von „geplant/teilweise“ auf den korrekten Status aktualisiert wurde.
