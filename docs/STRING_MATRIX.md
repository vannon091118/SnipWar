# STRING MATRIX — SnipWar StringName-/Event-Konstanten

> **Zweck:** Zentrale, LLM-freundliche Referenz aller StringName-Konstanten,
> EventBus-Typen, History-Event-Typen und Status-Strings. Jeder Eintrag nennt
> den **Wert**, die **Konstante** (falls vorhanden) und die **Quelldatei**.
> Diese Matrix ist die Anti-Drift-Quelle: Neue Strings gehören in
> `game_constants.gd` (Config) oder hier dokumentiert — nicht als verstreute
> Literale.
>
> **Pflege:** Bei jeder neuen StringName-Konstante diesen Index aktualisieren.
> Preflight `concept_index` + `global_search` durchsuchen diese Datei.

---

## 1. Fraktionen (Faction-IDs)

| Wert | Konstante | Quelle | Bedeutung |
|------|-----------|--------|-----------|
| `a` | `FACTION_PLAYER` | `game_constants.gd:8`, `game_state.gd:21` | Spieler-Fraktion |
| `b` | `FACTION_CPU` | `game_constants.gd:9`, `game_state.gd:22` | CPU-Fraktion |
| `neutral` | `FACTION_NEUTRAL` | `game_constants.gd:10`, `game_state.gd:23` | Besiedelte Neutrale |
| `uninhabited` | `FACTION_UNINHABITED` | `game_constants.gd:11`, `game_state.gd:24` | Unbesiedelte, kolonisierbar |

## 2. Ressourcen

| Wert | Konstante | Quelle |
|------|-----------|--------|
| `energy` | `RES_ENERGY` | `game_constants.gd:19`, `game_state.gd:21` |
| `biomass` | `RES_BIOMASS` | `game_constants.gd:20`, `game_state.gd:22` |
| `rare` | `RES_RARE` | `game_constants.gd:21`, `game_state.gd:23` |
| `material` | `RES_MATERIAL` | `game_constants.gd:22`, `game_state.gd:24` |
| `volatile` | `RES_VOLATILE` | `game_constants.gd:23`, `game_state.gd:25` |

Aggregat: `ALL_RESOURCES: Array[StringName]` (game_state.gd).

## 3. Missions-Typen

| Wert | Konstante | Quelle |
|------|-----------|--------|
| `military` | `MISSION_MILITARY` | `game_constants.gd:13`, `game_state.gd` |
| `cargo` | `MISSION_CARGO` | `game_constants.gd:14` |
| `colony` | `MISSION_COLONY` | `game_constants.gd:15` |
| `collect` | `MISSION_COLLECT` | `game_constants.gd:16` |

## 4. Technologien (spezielle IDs)

| Wert | Konstante | Quelle |
|------|-----------|--------|
| `worker_automation` | `TECH_WORKER_AUTOMATION` | `game_constants.gd:17`, `game_state.gd` |

## 5. EventBus-Typen (game_event channel)

**Quelle:** `scripts/state/event_bus.gd` (Signal `game_event(type, data)`),
Emittiert via `GameState._dispatch_event()` (game_state.gd) und
`ConflictManager`. Konsumenten: `EventLog`, `WorldChronicle`.

| Event-Typ | Bedeutung | Payload (Kernfelder) |
|-----------|-----------|----------------------|
| `run_started` | Neuer Run | `run_id`, `layout_seed` |
| `replay_started` | Replay | `run_id`, `layout_seed` |
| `faction_changed` | Besitzwechsel | `planet_id`, `old_faction`, `new_faction` |
| `planet_discovered` | Entdeckung | `faction`, `planet_id` |
| `planet_scanned` | Scan | `faction`, `planet_id`, `resource_id`, `size_id`, `build_slots` |
| `faction_resources_changed` | Vault-Änderung | `faction`, `resource_id`, `new_amount` |
| `credits_changed` | Credits | `faction`, `new_amount` |
| `workers_reserved` | Worker reserviert | `planet_id`, `job_id`, `amount` |
| `workers_released` | Worker freigegeben | `planet_id`, `job_id`, `amount` |
| `planet_upgraded` | Upgrade | `planet_id`, `upgrade_id` |
| `resource_generated` | Produktion | `planet_id`, `resource_id`, `amount` |
| `resources_collected` | Einsammeln | `faction`, `planet_id`, `resource_id`, `amount` |
| `gathering_started` | Sammeln beginnt | `faction`, `planet_id`, `workers` |
| `gathering_withdrawn` | Sammeln beendet | `faction`, `planet_id`, `workers` |
| `worker_factory_built` | Fabrik | `planet_id` |
| `refinery_converted` | Raffinerie | `planet_id`, `faction`, `consumed`, `produced` |
| `local_resources_changed` | Planet-Vorrat | `planet_id`, `resource_id`, `new_amount` |
| `resource_transferred` | Transfer | `from_planet`, `to_planet`, `resource_id`, `amount` |
| `planet_building_placed` | Gebäude | `planet_id`, `building_id`, `q`, `r` |
| `planet_building_destroyed` | Gebäude zerstört | `planet_id`, `q`, `r` |
| `worker_transport_started` | Transport | `transport_id`, `faction`, `amount` |
| `worker_transport_phase_changed` | Phase | `transport_id`, `phase` |
| `technology_researched` | Forschung | `faction`, `technology_id` |
| `planet_technology_researched` | Planet-Forschung | `planet_id`, `technology_id` |
| `research_started` | Forschung beginnt | `faction`, `technology_id`, `remaining` |
| `mid_game_started` | Midgame | `faction` |
| `milestone_reached` | Meilenstein | `faction`, `milestone_id` |
| `ship_part_purchased` | Teil gekauft | `planet_id`, `part_id` |
| `ship_assembled` | Schiff gebaut | `planet_id`, `ship_id` |
| `ship_disassembled` | Schiff zerlegt | `planet_id`, `ship_id` |
| `ship_launched` | Schiff gestartet | `planet_id`, `ship_id`, `role` |
| `ship_lost` | Schiff verloren | `planet_id`, `ship_id` |
| `ship_dispatched` | Schiff entsandt | — |
| `ship_arrived` | Schiff angekommen | — |
| `ship_build_started` | Bau beginnt | `planet_id`, `ship_id`, `remaining` |
| `research_ship_task_completed` | Forschungsauftrag | `mission_id`, `target_planet_id`, `task_type` |
| `research_ship_idle` | Forschungs-Schiff idle | `ship_id`, `planet_id` |
| `persistent_ship_changed` | Flottenstatus | `ship_id`, `status` |

## 6. Transit-Status (TransitRecord)

**Quelle:** `scripts/config/transit_record.gd`

| Wert | Konstante |
|------|-----------|
| `in_flight` | `STATUS_IN_FLIGHT` |
| `engaged` | `STATUS_ENGAGED` |
| `arrived` | `STATUS_ARRIVED` |
| `resolved` | `STATUS_RESOLVED` |
| `cancelled` | `STATUS_CANCELLED` |

## 7. History-Event-Typen (WorldChronicle)

**Quelle:** `scripts/history/simulation/history_event_factory.gd` +
`history_event.gd` (Doku-Kommentar). Erzeugt von `HistorySimulator`.

| Event-Typ | Bedeutung |
|-----------|-----------|
| `alliance` | Bündnis geschlossen |
| `build` | Bau/Infrastruktur |
| `colony` | Kolonie gegründet |
| `conquest` | Eroberung |
| `defeat` | Niederlage |
| `peace_treaty` | Friedensschluss |
| `research` | Forschung/Technologie |
| `rivalry` | Rivalität |
| `trade` | Handel |
| `war_declared` | Kriegserklärung |

> **Doku-Drift bekannt:** `history_event.gd`-Kommentar listet zusätzlich
> `attack, defend, capture, abandon, die, succeed, fail` — diese werden von
> der Factory **nicht** erzeugt (nur die 10 oben; `partial`/`pressure`/
> `success` als Ergebnis-Modifikatoren). Siehe `docs/FINDINGS.md`.

## 8. Character-/Faction-Moods (History-Simulation)

| Wert | Konstante/Quelle |
|------|------------------|
| `ambitious` | `world_state.gd` reset-Defaults |
| `cautious` | `world_state.gd` |
| `balanced` | `world_state.gd` |

## 9. Domänen-Zustands-Strings

| Wert | Kontext | Quelle |
|------|---------|--------|
| `homeworld` | Planet-Rolle | `faction_domain.gd` |
| `second_planet` | Planet-Rolle | `faction_domain.gd` |
| `active` / `queued` / `completed` / `cancelled` | Missions-/Job-Status | `ship_domain.gd`, `economy_domain.gd` |
| `idle` / `in_transit` / `delivered` | Schiffs-/Transport-Status | `ship_domain.gd` |
| `scan` | Scan-Mission | `ship_domain.gd` |

## 10. Architektur-Regeln (String-Hygiene)

1. **Config-Resources dürfen GameState nicht referenzieren** (Compile-Zyklus,
   siehe Godot-Pitfall). Neue String-Konstanten für Config → `game_constants.gd`.
2. **EventBus-Typen** sind StringName-Literale an der Emit-Stelle; Konsumenten
   matchen per `StringName`-Vergleich. Neue Typen hier eintragen.
3. **History-Event-Typen** leben in `history_event_factory.gd` — neue Typen
   brauchen Factory-Branch + Eintrag in dieser Matrix.
4. **`StringName` vs. `String`:** IDs sind StringName (schneller Vergleich),
   Anzeigetexte sind String (Lokalisierung). Nie mischen in Dictionaries.