<div align="center">

```
╔══════════════════════════════════════════════════════════════╗
║   TECHNISCHES FELDHANDBUCH // EISEN-GRENZE                   ║
║   KLASSIFIZIERUNG: INTERN (aber wir versionieren es eh)      ║
║   DOKTRIN: Code schlägt Dokument. Immer.                     ║
╚══════════════════════════════════════════════════════════════╝
```

</div>

# SnipWar Design Contract

> *„Wenn dieses Dokument und der Code voneinander abweichen, gilt der Code.*<br/>
> *Wer dem Dokument blind vertraut, hat noch nicht genug Commits gesehen.“*

**Stand:** August 2026<br/>
**Quelle:** Laufzeitcode, Resources, Szenen und `scripts/preflight.gd`.<br/>
**Regel:** Wenn dieses Dokument und der Code voneinander abweichen, gilt der Code. Eine geplante Regel darf hier erst als implementiert erscheinen, wenn sie einen Laufzeitverbraucher und Preflight-Abdeckung besitzt.

---

*📖 Lore: [`LORE.md`](LORE.md) — 📡 Frontlage: [`README.md`](README.md) — 🤖 Agenten-Leitfaden: [`AGENTS.md`](AGENTS.md) — 🗺️ Dokumentations-Index: [`docs/README.md`](docs/README.md)*

---

## 1. Aktueller Status

SnipWar ist ein strategischer Overworld-Prototyp mit funktionierendem Karten-, Transit-, Ressourcen-, Forschungs-, Upgrade-, Scout- und deterministischem Konfliktkern. Die Phasen 0 bis 7 (EffectDefinition, Trait-Erweiterungen, Planetensignaturen, Raffinerie-Konvertierung, Perimeter-Slots & Reichweite, CompositeShipView, FleetSnapshot, FleetBattleSimulator, ConquestSimulator und Replay-Szenen) sind implementiert und in `scripts/preflight.gd` verifiziert.

Der Startpunkt ist `scenes/backgrounds/starfield_background.tscn`. `GameState` und `EventLog` sind Autoloads. `StarfieldBackground._enter_tree()` wählt das aktive Szenario, finalisiert den Layout-Seed und generiert den Planetenkatalog, bevor es GameState, PlanetField und MeteorField konfiguriert; `Bootstrap` dealt danach nur die Ressourcen.

## 2. Aktiver Katalog und Szenarien

Der Sektor wird bei jedem Start aus dem Baustein-Pool generiert (`WorldGenerator.generate_catalog`). Der Default-Sektor nutzt `chunk_size = 3` (infinite/prozedurale Welt): ein Template-Planet wird als Chunk-Seed erzeugt, der `ChunkCoordinator` instantiiert weitere Planeten nach Bedarf. Bei `chunk_size = 0` (Legacy) werden `target_planet_count` fixe Planeten erzeugt — zwei Homeworlds (`p0` = Player/Faction `a`, `p1` = CPU/Faction `b`) und neutrale Welten. Texturen, Tints und Namen entstehen seed-deterministisch via `compose_planet()`/`generate_planet_name()` aus 10 Baustein-Typen (Ember, Ocean, Ice, Violet, Desert, Toxic, Storm, Volcanic, Paper, Golden) mit je 4 Varianten.

Interne Faction-IDs sind `a`, `b` und `neutral`; die semantischen Namen Player/CPU werden nur in UI und Meldungen verwendet.

Es gibt zwei Szenarien:

- `default`: 960×540, freie Zielauswahl (`all_planets`), zufälliger Laufzeit-Seed.
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

Navigation erzeugt genau einen Moon-/Comet-Waypoint pro Layout-Nachbarschaftskante und überlagert diese Kanten mit einem prozentualen K-Nearest-Langstrecken-Layer (`WorldConfig.graph_neighbor_ratio`: `ceil((n-1) × ratio)` nächste Nachbarn je Planet, symmetrisch dedupliziert, durch `max_extra_edges` gedeckelt). Die KNN-Kanten verbinden Planeten direkt ohne Waypoint-Mittelpunkt; AStar2D wählt automatisch den kürzeren Weg. `NavigationField` ist die einzige Quelle der Wahrheit: `get_neighbors_for_planet()` liefert die vereinigte Nachbarschaft an `PlanetNetwork.get_neighbors()` und damit an Preview, Worker-Transit, Scout und ShipBase. `find_route()` liefert den gemeinsamen Pfad für Preview und Transit. Das Standardrouting erlaubt jedes Ziel, routet aber trotzdem über dieses Graphnetz; `wide` beschränkt die Zielliste auf Nachbarn.

Das Layout skaliert über `WorldGenerator` und `WorldConfig`: `target_planet_count` bestimmt die Größe des seed-deterministisch generierten Katalogs (zwei Homeworlds an Index 0/1, danach neutrale Welten aus den Baustein-Texturen); `columns = 0` leitet die Spaltenzahl aus dem Seitenverhältnis ab; `extra_large_ratio`/`large_ratio` skalieren Größenklassen prozentual. `WorldConfig.growth_factor` ist ein multiplikativer Flächenfaktor (1.0 = Standard): `WorldGenerator.resolve_runtime_world` dupliziert die authored WorldConfig vor dem Scene-Boot und wendet `sqrt(growth_factor)` auf `design_size` und `growth_factor` linear auf `target_planet_count` an, sodass die strategische Dichte stabil bleibt. Die Mutation landet nur auf der Runtime-Kopie; die `.tres`-Datei wird nie überschrieben. `resolved_columns()`, `resolved_size_class_counts()`, `resolved_design_size()` und `resolved_target_planet_count()` sind die gemeinsame Quelle für `SeededLayout`, `NavigationField`, `PlanetNetwork` und `MeteorField`. Der Hintergrund rendert in Weltkoordinaten (`design_size`), nicht in Viewport-Koordinaten, damit eine über den Viewport hinauswachsende Welt (FOV/LoD) konsistent bleibt.

### Unendliche prozedurale Chunk-Welt

Wenn `WorldConfig.chunk_size > 0` ist, ist die Welt unendlich und erweitert sich prozedurial nach und nach, wenn der Spieler eigene Planeten erobert und die FoV-Region wächst. `chunk_size = 0` (Default) aktiviert den Legacy-Modus mit fixem Grid. `ChunkCoordinator` (Kind von `PlanetField`) verwaltet den Chunk-Lebenszyklus: lazy Generierung, lightweight Cache (`ChunkPlanetData` — keine Node-Instanzen), LRU-Eviction und sicheres Planet-Cycling (Halt-Phase → Deferred `queue_free` mit `has_planet()`-Guard). Der Chunk-Seed nutzt eine LCNG-Formel (int64, keine XOR/abs()-Überläufe). Planeten werden aus Bausteinen komponiert (`composition_base_texture` + `composition_tint` + Decals aus `WorldConfig.composition_decal_pool`). `deal_resources_for_planets()` ist eine separate Lazy-Methode ohne `clear()`. `NavigationField` hat inkrementelle `add_planet()`/`remove_planet()` mit cell-basierten pending edges. `deep_space_scanner` (Tier 2, Parent: `orbital_station`) erweitert das FoV über `fov_radius_bonus`.

## 4. GameState als autoritative Quelle (Domain-Facade)

`GameState` fungiert als zentrale Fassade (`Facade-Pattern`) und delegiert spezialisierte Domänenaufgaben an 4 interne Sub-Manager (`scripts/state/domains/`):

1. **`FactionDomain`**: Ownership/Factions, Homeworlds, Start-Worker, Discovery- und Scan-Intel, Milestones & Starter-Scouts.
2. **`EconomyDomain`**: Faction-Vaults, Ressourcen-Deals (`deal_resources`), Planet-Upgrades, Worker-Factories, persistente Gatherer & Wartung.
3. **`TechDomain`**: Globale und planetare Technologien, Forschungs-Voraussetzungen und zeitgesteuerte Research-Jobs.
4. **`ShipDomain`**: Schiffsteile-Inventare, modulare Schiffsmontage (`assemble_ship`), Zerlegung, Bau-Jobs und Flotten-Snapshots (`FleetSnapshot`).

Alle öffentlichen APIs, Signale und Preflight-Schnittstellen von `GameState` bleiben als 100% abwärtskompatible Delegaten erhalten.

Planeten spiegeln Faction-Änderungen über `faction_changed`. Ein Capture darf nicht durch direkte Planet-zu-Planet-Ownership-Logik erfolgen.

`reset_from_catalog()` setzt alle 4 Domänen zurück. `PlanetDetails` entfernt daraufhin Upgrade-Strukturen.

### UI- & Komponenten-Architektur
- **`TechnologyMenu`**: Wurde in 4 spezialisierte Sub-Views unterteilt (`scripts/ui/tech_menu/`):
  - `TechResearchView`: Globale Technologie-Karten & Countdowns.
  - `TechScoutView`: Scout-Flug & Worker-Fertiger-Bau.
  - `TechShipBuilderView`: Schiffsteile-Shop, Hangar-Montage & Job-Countdowns.
  - `TechPlanetView`: Bekannte Planeten, Intel-Analyse & planetare Forschung.
- **`UIBaseUtils`** (`scripts/ui/ui_base_utils.gd`): Zentraler Helper für `style_box`, `make_label`, `make_separator` und `apply_button_theme`.
- **`PlanetView`** (`scripts/objects/planets/view/planet_view.gd`): Kapselt reine CanvasItem-Zeichenroutinen (`_draw`, Faction-Ringe, StrengthLabel-Positionierung) getrennt von der Gameplay-Logik in `Planet.gd`.

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

Der Default-Katalog enthält 17 `PlanetUpgradeDefinition`-Einträge in vier Zweigen:

- Economy: `extractor`, `refinery`, `trade_post`, `automated_mine`, `trade_hub`
- Military: `shipyard`, `war_shipyard`, `colony_shipyard`, `defense_grid`
- Tech: `tech_center`, `weapon_lab`, `armor_lab`
- Infrastructure: `orbital_station`, `colony_hub`, `trade_network`, `comms_array`, `deep_space_scanner`

Implementiert sind:

- Parent-Prerequisites
- gegenseitige Exklusivität
- Ressourcen- und Worker-Kosten
- Technologie-Gates, wo ein Upgrade sie referenziert
- sichtbare `UpgradeStructure_<id>`-Kinder in `PlanetDetails`
- Trait-Verbraucher für `production_boost`, `worker_spawn_bonus`, `defense_rating`, `transfer_speed_multiplier`, `cluster_tier_bonus` und Maintenance

Wichtige Grenzen des aktuellen Vertrags:

- `refinery` konvertiert 2 Material + 1 Energy → 1 Rare über `convert_refinery_resources()` (mit Energy-Refund); die Konvertierung ist noch nicht als serialisierbare Definition ausgelagert.
- `trade_post` und ähnliche Geschwindigkeitsboni sind generische Transfer-Speed-Modifikatoren; es gibt noch kein separates Frachter-Subsystem.
- `cluster_tier_bonus` verändert nur die sichtbare Clusterstufe, nicht logische Kapazität, Packung, Fluglast oder Ankunftsmenge.
- `perimeter_slots_bonus` speist `Planet.get_perimeter_slots()` und `range_bonus` `Planet.get_defense_range()`; beide fließen als Tower-Slots/Defense-Reichweite in `ConquestSimulator.simulate_conquest()` ein.
- `weapon_lab` und `armor_lab` erzeugen noch keinen allgemeinen Transformer-Pool für Mechs oder Schiffe.
- Asset-Komposition existiert für Planet-Upgrade-Strukturen, aber noch nicht als allgemeiner Objekt×Transformer-Child-Pool.

## 7. Forschung, Discovery und Scouts

Der Default-TechnologyCatalog enthält 14 Technologien:

- Ship-Technologien: `shipyard_construction`, `scout_hull`, `scanner_drone`, `weapon_systems`, `worker_automation`, `advanced_propulsion`, `heavy_armor_plating`, `deep_scan`, `long_range_sensors`
- Mech-Technologie: `mech_frame` — sichtbar, aber bis Layer 3 inert
- Planet-Technologien: `planetary_survey`, `planetary_extraction`, `automated_refinery`, `bulk_processing`

Globale Forschung liegt pro Fraktion vor. Planetare Forschung liegt pro Planet vor und darf nur auf einem eigenen bekannten Planeten stattfinden. Planetare Forschung beeinflusst aktuell die Produktionsmultiplikation.

Der neue Spieler erhält genau einen kostenlosen Start-Scout. Dieser benötigt zunächst keine Werft- oder Scout-Forschung, aber weiterhin einen eigenen Planeten, einen freien Bauplatz und einen unbekannten neutralen Layout-Nachbarn als Ziel. Nach Verbrauch des Start-Scouts benötigen weitere Scouts Upgrade `shipyard`, `scout_hull`, `scanner_drone`, Baukosten und einen freien Bauplatz.

CPU-Homeworlds, bekannte Planeten und Nicht-Nachbarn sind keine Scout-Ziele. `ScoutShip` fliegt `NavigationField.find_route()`, scannt bei Ankunft Ressourcen-ID, Größen-ID und Bauplätze und wird anschließend freigegeben; der Scan bleibt bei Ankunft sofortig.

## 8. Ship Builder: aktueller Umfang

`ShipPartCatalog` enthält die Slottypen Hull, Antrieb, Waffe, Schild, Scanner und Module sowie zwei maximale Modulplätze. Der Default-Katalog enthält drei Hüllen (T1/T2/T3), mehrere Antriebe, Impulsgeschütze und Schilde, einen Scanner und drei Module; Antrieb, Waffe und Schild tragen Varianten-Pools (gewichtete, seed-deterministische Auswahl mit sichtbaren Overlays).

**Asset-Verzeichnisse:** Rümpfe liegen in `assets/objects/ships/hulls/` (`hull_t1_scout.svg`, `hull_t1_courier.svg`, `hull_t1_interceptor.svg`, `hull_t2_destroyer.svg`, `hull_t2_carrier.svg`, `hull_t2_multirole.svg`, `hull_t3_colony.svg`, `hull_t3_dreadnought.svg`, `hull_t3_expansion.svg`). Komponenten liegen in `assets/objects/ships/components/` mit Prefix `drive_`/`weapon_`/`shield_`/`scanner_`/`module_` gefolgt von Tier und Name (z.B. `weapon_t1_beam.svg`, `shield_t2_phase.svg`). Struktur-Assets für Planeten-Upgrades sind tiered in `assets/objects/structures/` (`structure_shipyard_l1/l2/l3.svg` etc., 17 Upgrade-Typen × 3 Tiers + 3 standalone = 54 Dateien). Planeten-Basistexte inkl. v2/v3/v4-Varianten liegen in `assets/objects/planets/` (`planet_01_ember.svg` + `_v2/_v3/_v4.svg` für 10 Planetentypen). Decal-Overlays in `assets/objects/planets/decals/` (18 Typen wie `decal_aurora_arcs.svg`, `decal_lava_flows.svg`) werden über `WorldConfig.composition_decal_pool` komponiert. UI-Hintergründe in `assets/ui/backgrounds/` (6 Dateien für Main Menu, Pause, Tech Menu, Ship Hangar, Planet Panel, Modal).

Kaufen, Montieren und Zerlegen sind in `GameState`, `ShipManager` und `TechnologyMenu` implementiert. Jede Assembly verlangt einen vollständigen Loadout:

```text
hull + drive + shield + scanner + optional weapon + module_ids
```

Drive und Shield sind Pflichtfelder in allen Assembly-APIs. Ein unbewaffneter Loadout wird als Kolonieschiff geführt, ein Loadout mit Waffe als Militärschiff. Worker-Fertiger und Scout bleiben separate Pfade.

**Tech-Gating:** Jedes Bauteil trägt `required_tech_id`; der Kauf ist gesperrt, bis die Fraktion die Technologie erforscht hat. Der Default-Katalog enthält T1/T2/T3-Rümpfe sowie mehrere auswählbare Drive-, Weapon- und Shield-Komponenten. Jede dieser Komponenten besitzt zusätzlich einen gewichteten, seed-deterministischen Variant-Pool mit sichtbarem Overlay und Trait-Readback.

**Timer statt Sofort-Freischaltung:** `TechnologyDefinition.research_time` und `ShipPartDefinition.build_time` machen Forschung und Montage zu zeitgesteuerten Aufträgen in `GameState` (`_research_jobs`, `_ship_build_jobs`). Kosten werden beim Start gezahlt; `advance_research()`/`advance_builds()` treiben die Jobs im Live-Spiel über `_process` voran (Preflight friert sie über `set_jobs_auto_advance(false)` ein und tickt deterministisch). `technology_researched`/`ship_assembled` feuern erst bei Abschluss.

**Pacing:** Der Rumpf trägt die Tier-Basiszeit T1 = 63 s, T2 = 123 s, T3 = 183 s. Drive, Shield, Scanner, Weapon und Utilities addieren komponentenabhängige Montagezeit, die mit der Rumpfstufe skaliert. Der Hangar zeigt Slot, Variant, Trait, abgeleitete Stats und die verbleibende Montagezeit als Live-Readback mit Tooltip.

Montierte Assemblies werden über `ConflictManager` als echte `ShipBase`-Transits gestartet. Kolonieschiffe besiedeln ausschließlich gescannte neutrale Ziele; die erste erfolgreiche Kolonisierung setzt den idempotenten Meilenstein `first_colony`. Militärische Assemblies werden am Ziel über FleetBattle-/Conquest-Simulatoren aufgelöst. Worker-Cluster bleiben für Worker-Missionen wie Collect und Cargo erhalten.

## 9. Missionen, Transit und Conflict Resolve

`WorkerManager` unterstützt:

- `military`: Worker-Missionen nutzen den bestehenden Arrival-Resolve; militärische ShipBase-Assemblies nutzen FleetBattle-/Conquest-Auflösung
- `colony`: ShipBase-Kolonieschiffe besiedeln ausschließlich gescannte neutrale Planeten und markieren `first_colony`; Worker-Kolonietransit bleibt als Legacy-Pfad gültig
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

Militärischer Resolve läuft über `PlanetArrivalResolver` in zwei Pfaden:

- Worker-Military (`resolve_military_arrival`) → `ConquestSimulator.simulate_conquest()`: bei Capture wechselt die Faction über `GameState.set_faction()` und Überlebende werden als Worker registriert; bei Abwehr werden bis zu `incoming` Worker entfernt.
- Schiffs-Ankunft (`resolve_ship_arrival`) → Kolonieschiff besiedelt ausschließlich gescannte neutrale Ziele; eine Defender-Flotte wird über `FleetBattleSimulator` aufgelöst (fleet-vs-fleet), ohne Defender über `ConquestSimulator` (fleet-vs-ground).

Beide Simulatoren sind deterministisch; `BattleScene` und `ConquestScene` illustrieren nur bereits berechnete Ergebnisse.

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
- mehrere parallel steuerbare Schiffsklassen und vollständige Fleet-Missionsauswahl
- ~~aktive Layer-2-Flotten-KI und animierte Raumkampf-Cutscene~~ ✅ implementiert: `BattleScene`, `IngamePlayerControls`, `SceneDirector`, `GameCycleManager`
- ~~Tower-Defense, Türme, aktive Garnisonsverteilung und Layer-3-Eroberung~~ ✅ implementiert: `ConquestSimulator`, `ConquestScene`, `PlanetGrid`, `BuildingCatalog`, 7 Gebäude-Defs
- ~~Ship-as-Minion-Adapter~~ ✅ implementiert: `AssaultMinionDefinition.from_ship()`
- Mech-Kampflogik (Layer 3 inert, `mech_frame` nur als Tech-Registrierung)
- Planetentypen als echte Ressourcen-Signaturen
- Ressourcenkonvertierung, Siegbedingungen und Kampagnenzustand

## 14. Verifikation

Die zentrale Regression-Suite ist `scripts/preflight.gd`. Sie deckt unter anderem Scene-Boot, Kataloge, Ressourcen-Deal, Seed-Variation, Größenprofile, Details, Navigation, UI, Upgrades, Missionen, CPU-Hooks, Scouts, Ship-Builder, EventLog, Kontextmenü und Pause-Verhalten ab.

Ein separater Main-Scene-Smoke-Test ist:

```text
godot --headless --path . --quit-after 2
```

Die Suite wurde mit Godot 4.7.2 aus dem bereitgestellten lokalen Binary ausgeführt und meldete `RESULT: PASSED (29 constraints)`; auch der Main-Scene-Smoke-Test mit `--quit-after 2` war erfolgreich. Die Aussagen oben wurden aus Code, Resources, den vorhandenen Preflight-Assertions und diesem Lauf abgeleitet.

## 15. Feature-Matrix

**Statusbegriffe:**

- **Implementiert:** Laufzeitpfad vorhanden und durch Preflight oder den verifizierten Smoke-Test abgedeckt.
- **Teilweise:** Ein nutzbarer Slice existiert, aber der beschriebene Zielumfang oder ein geplanter Verbraucher fehlt.
- **Geplant:** Noch kein autoritativer Laufzeitpfad und keine Preflight-Abdeckung.

| Bereich | Feature | Status | Code-/Resource-Grenze |
|---|---|---|---|
| Fundament | Szenarioauswahl, 10 Baustein-Typen (40 Texturen), prozedurale Chunk-Welt (chunk_size=3) oder Legacy-Fix-Ansatz | Implementiert | `starfield_background.gd`, `scenario_catalog.tres`, `world_generator.gd`, `chunk_coordinator.gd` |
| Fundament | Seed-Layout, Größenprofile, Startgarnisonen und Bauplätze | Implementiert | `seeded_layout.gd`, `planet_size_profile.gd` |
| Präsentation | PlanetDetails, Toxic-Garantien, Fidelity-Profile, Meteore, Starfield-Batches | Implementiert | `planet_details.gd`, `starfield_background.gd`, `preflight.gd` |
| Navigation | Nachbarschaftsgraph, Waypoints, Routen, `all_planets`/`neighbors_only` | Implementiert | `navigation_field.gd`, `planet_network.gd` |
| Navigation | K-Nearest-Langstrecken-Layer, Edge-Budget, KNN als AStar-Zusatzkanten | Implementiert | `world_generator.gd`, `navigation_field.gd` |
| Weltwachstum | `growth_factor`-Flächenfaktor, sqrt-Skalierung X/Y, Runtime-Duplikat schützt `.tres` | Implementiert | `world_config.gd`, `world_generator.gd`, `starfield_background.gd` |
| Prozedurale Welt | Unendliches Chunk-Grid, Baustein-Planeten, FoV-Cycling, inkrementelle Navigation | Implementiert | `chunk_coordinator.gd`, `world_config.gd`, `world_generator.gd`, `navigation_field.gd`, `planet.gd`, `preflight.gd` |
| Besitz | GameState-Ownership, Faction-Signale, Homeworld- und Capture-Zustand | Implementiert | `game_state.gd`, `planet.gd` |
| Ressourcen | Fünf Ressourcen, seed-deterministischer Deal, Homeworld-Differenz, Vaults | Implementiert | `game_state.gd`, `resource_pool_default.tres` |
| Wirtschaft | Passive Produktion, Maintenance, Gather-Timer und persistente Sammeltrupps | Implementiert | `economy_manager.gd`, `game_state.gd`, `planet.gd` |
| Ressourcenmodell | Planetentyp als echte Ressourcen-Signatur | Geplant | Vorhandene Mapping-Hilfsmethode wird nicht vom Deal/Production-Pfad verwendet |
| Wirtschaft | Raffinerie als tatsächliche Ressourcen-Konvertierung | Implementiert | `convert_refinery_resources()` (2 Material + 1 Energy → 1 Rare, Energy-Refund) |
| Upgrades | 17 Upgrades, vier Branches, Kosten, Parent-/Exklusivitätsregeln | Implementiert | `planet_upgrade_catalog_default.tres`, `game_state.gd` |
| Upgrades | Sichtbare Upgrade-Strukturen auf Planeten | Implementiert | `planet_details.gd`, `planet.gd` |
| Traits | Produktion, Spawnrate, Defense-Rating, Transfer-Speed, sichtbarer Tier-Bonus | Implementiert | `trait_definition.gd`, `planet.gd`, Transitpfad |
| Traits | Perimeter-Slots & Reichweite im Conquest-Pfad; allgemeiner Objekt×Transformer-Child-Pool | Teilweise | Perimeter/Reichweite speisen `get_perimeter_slots()`/`get_defense_range()`; der allgemeine Kompositions-Pool fehlt noch |
| Forschung | Globale/planetare Technologien, Prerequisites und Discovery-Gates | Implementiert | `technology_catalog.gd`, `game_state.gd` |
| Scouts | Ein kostenloser Start-Scout, danach Werft-/Tech-/Kosten-/Nachbar-Gates, Flug, Scan-Intel und Freigabe | Implementiert | `ship_manager.gd`, `scout_ship.gd`, `game_state.gd` |
| Ship Builder | Teile kaufen, vollständige Drive-/Shield-Loadouts montieren, zerlegen, Varianten und Readback | Implementiert | `game_state.gd`, `ship_manager.gd`, `technology_menu.gd`, `shipyard_hangar.gd` |
| Schiffe | Assemblies als aktive ShipBase-Transits mit Loadout-Traits und Rollen | Implementiert | `conflict_manager.gd`, `ship_base.gd`, `fleet_snapshot.gd` |
| Transit | Slider, Flugzeit, K/M/L-Packung, Formation, Ankunfts-Resolve | Implementiert | `worker_manager.gd`, `worker_cluster.gd`, `flight_time.gd` |
| Missionen | Military, Colony, Cargo und Collect mit missionsabhängigen Gates | Implementiert | `planet.gd`, `worker_manager.gd`, `planet_network.gd` |
| CPU | Timer-basierter Colony-/Cargo-/Military-Dispatcher | Implementiert | `cpu_dispatch_ai.gd`, `cpu_dispatch_default.tres` |
| Konflikt | Deterministischer Worker- plus Defense-Rating-Resolve | Implementiert | `Planet.resolve_arrival()` |
| Layer 2 | Deterministische Flottensimulation mit BattleResult/Event-Stream | Implementiert | `FleetBattleSimulator`, `BattleContext`, `CombatReplay`, `RouteEngagementResolver` |
| Layer 2 | Animierte Raumschlacht als Replay/Cutscene | Implementiert | `BattleScene`, `IngamePlayerControls`, `SceneDirector`, `GameCycleManager` |
| Layer 3 | Planetare Tower-Defense und aktive Verteidigung | Implementiert | `ConquestSimulator`, `ConquestScene`, `PlanetGrid`, `BuildingCatalog`, 7 Gebäude-Defs |
| Layer 3 | Ship-as-Minion-Adapter mit visueller/logischer Adaption | Implementiert | `AssaultMinionDefinition.from_ship()`, `ConquestScene` Minion-Spawning |
| Kampagne | `first_colony`-Meilenstein und persistenter Fortschrittsmarker | Teilweise | `game_state.gd`, `event_log.gd`; Dominanz-/Siegbedingungen bleiben später |
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

Der erste aktive Ship-Assembly-Slice ist implementiert: Dictionary-Zustand bleibt als kompatibler persistenter SSOT in `GameState`, während `ConflictManager` die autoritative Launch-/Transit-Orchestrierung übernimmt. Eine spätere typisierte Assembly-Resource kann diesen Zustand ersetzen, ohne `GameState` zum Scene-Manager zu machen.

1. Der aktuelle Assembly-Dictionary-Zustand enthält ID, Rolle, Ursprungsplanet, Loadout, Variant-IDs und Build-/Hangarstatus; eine typisierte Resource ist ein späterer Härtungsschritt.
2. `ShipPartDefinition` liefert slot-kompatible Traits, Varianten und visuelle Overlays. Hull, Scanner, Drive, Shield, Weapon und Utility bleiben getrennte Slots.
3. `GameState` hält Assembly-/Build-SSOT; `ConflictManager` reserviert durch atomaren Fleet-Aufbau, startet und löst ShipBase-Transits auf.
4. `ShipManager` bleibt für Kauf, Assembly, Scout und Hangar zuständig. `ConflictManager` übernimmt Fleet-Auswahl und Start.
5. ShipBase visualisiert den Loadout-Snapshot. `WorkerCluster` bleibt der Worker-Transit und wird nicht mit Schiffsstatus überladen.
6. Der erste aktive Slice unterstützt Kolonie- und Militär-Assemblies; der Scout-Scan bleibt separat und behält seine Tech-Gates.

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
- Jede Phase ergänzt eine neue `PreflightConstraintX`-Klasse in `scripts/preflight/` (registriert im `_ConstraintScripts`-Array von `preflight.gd`); keine bestehende Constraint wird mit globalem Reset umgangen.
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
