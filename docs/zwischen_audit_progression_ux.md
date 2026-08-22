# SNIPWAR — Verifiziertes Zwischen-Audit: Progression, UX, Controls, Atmosphäre

> **Erstellt:** 2026-08-22
> **Letzte Verifizierung:** 2026-08-22 — Jeder Claim gegen Code geprüft
> **Status:** Red-Only Audit → Wartet auf Build-Auftrag

---

## 1. DOMÄNEN-DELTA — Verifiziert

### 🔋 DOMÄNE 1: ECONOMIE

| Was | Status | Verifizierung | Klassifikation |
|---|---|---|---|
| **Upgrade-Maintenance** | ✅ WIRKT | `economy_domain.gd:756-764` — `generate_resources_for_planet()` iteriert alle Planet-Upgrades und zieht `maintenance_cost_resource` + `maintenance_credit_cost` ab. Wird im 10s Economy-Tick aufgerufen. | NICHTS ZU TUN |
| **Building-Maintenance** | ❌ NICHT IMPLEMENTIERT | `BuildingDefinition.maintenance_resources` existiert als Feld und wird validiert, aber **KEIN Code liest oder zieht diese Werte ab.** Nur Upgrade-Traits (über `trait_definition`) werden deducted. | NEUER CODE (~30L in EconomyManager) |
| **Credits als passives Einkommen** | ❌ DEAD END | `tick_trade_routes()` gibt Tolls als Credits — aber `register_trade_route()` wird **nur in Preflight-Tests** aufgerufen, nie im Gameplay. Kein UI zum Erstellen von Trade-Routes. | MINOR CODE: Trade-Route-Registrierung braucht UI oder Auto-Registrierung |
| **Trade-Post Kosten** | 20 Volatile + 5 Credits | `trade_post.tres`: `cost_resource = volatile`, `cost_amount = 20`. Kein `credit_cost` Override → Default = 5. Extractor: 15 Energy + 5 Credits. | NICHTS ZU TUN (oder Kosten anpassen) |
| **Gathering-Tick** | ✅ WIRKT | `economy_manager.gd:132-134` — `_on_gather_tick()` → `gather_now()` → `GameState.gather_income_tick()` | NICHTS ZU TUN |
| **Economy-Tick (Worker-Automation)** | ✅ WIRKT | `economy_manager.gd:128-130` — `_on_tick()` → `_tick_economy()` → iteriert Planeten → `generate_economy_resources()` → `generate_resources_for_planet()` (mit Maintenance) | NICHTS ZU TUN |
| **Credits nur ausgeben, nie verdienen** | ✅ KORREKT | Start 100 Credits. Kein passives Einkommen. Trade-Route-Toll existiert aber ist nicht nutzbar. | KRITISCH: Braucht Credits-Lösung |

**Korrigierte Empfehlung:** Die einfachste Lösung für Credits ist, die Gather-Tick um einen Credits-Anteil zu erweitern (z.B. +1 Credit pro besessenem Planet pro Gather-Tick). Das braucht ~10 Zeilen in `gather_income_tick()`.

---

### ⚔️ DOMÄNE 2: KAMPF & TRANSIT

| Was | Status | Verifizierung | Klassifikation |
|---|---|---|---|
| **Route-Engagement** | ✅ Voll | `route_engagement_solver.gd` detektiert Mid-Flight-Kämpfe | NICHTS ZU TUN |
| **Capture Decision** | ✅ Voll | `capture_decision_overlay.gd` zeigt Loot/Annex/Neutralize | NICHTS ZU TUN |
| **Fleet-Route-Linien (aktiver Planet)** | ✅ WIRKT | `planet_network.gd:193-206` — `_draw()` zeichnet pulsierende Route von Source→Destination | NICHTS ZU TUN |
| **Fleet-Route-Linien (ALLE Transits)** | ❌ FEHLT | Kein Code zeichnet Linien für in-flight Transits außer dem aktuell gewählten Planeten. `GameState.get_transit_records()` liefert die Daten. | VERKABELUNG (~15L in PlanetNetwork._process) |
| **Fleet-Follow Camera** | ✅ TEILWEISE DA | `fleet_overview.gd` → `focus_requested` Signal → `planet_network._on_fleet_overview_focus()` → `_center_camera_on()` → `MapCamera.position = target.global_position`. Aber: Focus-Button im FleetOverview ist ein kleiner Text-Button, nicht intuitiv. | VERKABELUNG (Signal existiert, nur UX-Verbesserung) |
| **Dispatch-Undo** | ❌ Nichts da | `GameState.complete_worker_transport(id, false)` existiert als API. Kein UI-Trigger. | MINOR CODE (~50L) |
| **Warning-Pulse** | ❌ Nichts da | `Planet._on_faction_changed()` existiert. Kein visuelles Feedback wenn Nachbar zu CPU wechselt. | VERKABELUNG (~10L) |

---

### 🔬 DOMÄNE 3: FORSCHUNG & PROGRESSION

| Was | Status | Verifizierung | Klassifikation |
|---|---|---|---|
| **14 Globale Techs** | ✅ Voll | `technology_catalog_default.tres` — 14 Techs mit Prerequisites, Exclusions, Timed Jobs | NICHTS ZU TUN |
| **Planetare Techs** | ✅ Voll | Sofort-Forschung via `research_planet_technology()` | NICHTS ZU TUN |
| **Milestone-System (Daten)** | ✅ Voll | 7 Milestones: `first_scan`, `first_transport`, `first_ship`, `second_planet`, `first_colony`, `first_worker_factory`, `first_escort` | NICHTS ZU TUN |
| **Milestone-Signal** | ✅ Voll | `GameState.milestone_reached` Signal existiert und wird von `FactionDomain.record_milestone()` emittiert | NICHTS ZU TUN |
| **Milestone-Belohnung** | ❌ FEHLT | `milestone_reached` Signal ist NICHT an Belohnungs-Logik gekoppelt. Kein `add_faction_credits()`, kein `EventLog.push()`. | VERKABELUNG (~20L in GameState oder neuem Handler) |
| **Onboarding-Hints** | ❌ Nichts da | Kein Code der "Was soll ich als nächstes tun?" liest | NEUER CODE (~80L) |
| **Sandbox Objectives** | ❌ Nichts da | Keine Config, kein HUD-Element | NEUER CODE (~80L Config + ~40L UI) |

---

### 🌍 DOMÄNE 4: WELT & KARTE

| Was | Status | Verifizierung | Klassifikation |
|---|---|---|---|
| **Fog of War** | ✅ Voll | `planet.gd` — 3 States (FOG/FRONTIER/VISIBLE), Shader, `_refresh_fog_of_war()` in PlanetNetwork | NICHTS ZU TUN |
| **Sector-Ownership-Overlay** | ❌ Nichts da | Kein Code der Owner-Sectors einfärbt. `GameState.all_owned_planets()` + `Planet.global_position` verfügbar. | NEUER CODE (~60L) |
| **Discovery-Highlight** | ❌ Nichts da | `GameState.planet_scanned` Signal existiert. Kein visuelles Feedback. | VERKABELUNG (~10L) |
| **Building-Complete Feedback** | ❌ Nichts da | `GameState.building_placed` Signal existiert. Kein Toast/Animation. | VERKABELUNG (~5L) |
| **Worker-Spawn Sichtbarkeit** | ❌ Nichts da | `Planet.worker_count_changed` Signal existiert. Timer-Data in `Planet._spawn_timer`. Keine Anzeige. | VERKABELUNG (~15L) |

---

### 🎮 DOMÄNE 5: STEUERUNG

| Was | Status | Verifizierung | Klassifikation |
|---|---|---|---|
| **Camera Pan (WASD)** | ✅ Voll | `map_camera.gd:52-62` — Input Map: W/S/A/D = camera_pan_* | NICHTS ZU TUN |
| **Camera Zoom** | ✅ Voll | Mausrad + Pinch-to-Zoom | NICHTS ZU TUN |
| **Planet-Select** | ✅ Voll | `planet.gd:240-280` — Left-Click + Touch + Long-Press | NICHTS ZU TUN |
| **Multi-Select** | ✅ Voll | `selection_service.gd` — Shift/Ctrl/LongPress Toggle | NICHTS ZU TUN |
| **Context Menu** | ✅ Voll | `context_menu_builder.gd` + `PopupMenu` | NICHTS ZU TUN |
| **Drag-to-Dispatch** | ✅ Voll | `map_camera.planet_drag_dropped` Signal | NICHTS ZU TUN |
| **Touch Ripple** | ✅ Voll | `touch_feedback_layer.gd` | NICHTS ZU TUN |
| **Mobile Virtual Buttons** | ❌ Nichts da | Kein D-Pad, keine Action-Buttons. | NEUER CODE (~150L) |
| **Keyboard Shortcuts** | ❌ Nichts da | Nur WASD + ESC + Space + Enter existieren. Kein T/B/Q/F. | VERKABELUNG (~20L Input-Map + Handler) |
| **"Close All" Shortcut** | ❌ Nichts da | ESC schließt nur eine Ebene. | VERKABELUNG (~5L) |

---

### 🔊 DOMÄNE 6: ATMOSPHÄRE & AUDIO

| Was | Status | Verifizierung | Klassifikation |
|---|---|---|---|
| **FloatingText** | ✅ Voll | `floating_text.gd` — `spawn()` mit Tween | NICHTS ZU TUN |
| **VaultBar Bounce** | ✅ Voll | `vault_bar.gd:refresh()` — Scale-Tween 1.02x | NICHTS ZU TUN |
| **Faction-Ringe** | ✅ Voll | `planet_view.gd` — `draw_planet_rings()` | NICHTS ZU TUN |
| **Strength-Label** | ✅ Voll | `planet_view.gd` — `update_strength_label()` | NICHTS ZU TUN |
| **Starfield Background** | ✅ Voll | `starfield_background.gd` — Parallax | NICHTS ZU TUN |
| **PaperDossier Animation** | ✅ Voll | `paper_dossier.gd` — Scale+Fade Tween | NICHTS ZU TUN |
| **Audio (gesamt)** | ❌ NULL | Kein AudioStream, kein AudioManager, kein Sound-Asset im Code. README erwähnt "atmosphärische Soundkulisse" aber nicht implementiert. | NEUES SYSTEM (~80L AudioManager + Assets) |
| **Ship Trail Partikel** | ❌ NULL | Kein CPUParticles2D an ShipBase. | NEUER CODE (~30L) |
| **Camera Shake** | ❌ NULL | Kein Code. `battle_started` Signal existiert in GameCycleManager. | VERKABELUNG (~15L) |
| **replay_started → UI** | ⚠️ SIGNAL IST DA, NICHT GEKOPPELT | `ConflictManager.replay_started` Signal existiert (Zeile 13), aber ist an **NICHTS** angeschlossen (0 Treffer für `replay_started.connect`). | VERKABELUNG |

---

### 🖥️ DOMÄNE 7: MENÜ & UI

| Was | Status | Verifizierung | Klassifikation |
|---|---|---|---|
| **PlanetPanel** | ✅ Voll | `planet_panel.gd` — Upgrade-Liste, Mission, Amount, Preview | NICHTS ZU TUN |
| **TechnologyMenu** | ✅ Voll | 4 Sub-Views | NICHTS ZU TUN |
| **PauseMenu** | ✅ Voll | ESC-Guard, Speichern/Menu | NICHTS ZU TUN |
| **PaperDossier** | ✅ Voll | 4 Dossier-Views (Planet/Werkstatt/Forschung/Economy) | NICHTS ZU TUN |
| **MessageFeed** | ✅ Voll | Toast-System | NICHTS ZU TUN |
| **FleetOverview** | ✅ Voll | `fleet_overview.gd` — Sidebar mit Ships + Planets, Focus-Handler zentriert Kamera. Verbunden mit `ConflictManager.get_active_ships()` und `SelectionService`. | NICHTS ZU TUN |
| **DossierLauncher** | ✅ Voll | 4 Buttons (Planet/Werkstatt/Forschung/Economy) auf Layer 40 | NICHTS ZU TUN |
| **Economy Dashboard** | ✅ Voll | `economy_window.gd` — persistentes Modul mit Icon-basierter Rohstoff-Übersicht, Produktionsquellen, Transport, Tick-Status; live via Signals; öffnet per ECONOMY-Button oder VaultBar-Klick | NICHTS ZU TUN |
| **Context-Hint Panel** | ❌ Nichts da | Kein "Was als nächstes?" | NEUER CODE (~80L) |

---

## 2. KORREKTE ZÄHLUNG

### Was NUR VERKABELT werden muss (Signal → existing API):
```
1. Milestone-Belohnungen:     milestone_reached → add_faction_credits + EventLog     ~20L
2. Fleet-Route-Linien:        _process() → get_transit_records() → draw_line         ~15L
3. Discovery-Highlight:       planet_scanned → Planet modulate tween                 ~10L
4. Building-Complete Toast:   building_placed → FloatingText.spawn()                  ~5L
5. Worker-Spawn-Anzeige:      worker_count_changed → Timer-Label aktualisieren       ~15L
6. Warning-Pulse:             faction_changed → roter Modulate-Pulse                 ~10L
7. Keyboard Shortcuts:        Input-Map + _unhandled_input Handler                   ~20L
8. Camera-Shake:              battle_started → MapCamera offset tween                ~15L
9. Replay→Audio-Trigger:      replay_started → AudioStreamPlayer.play()              ~5L
10. Trade-Route-Auto-Reg:     post-upgrade → register_trade_route()                  ~15L
                              ─────────────────────────────────────
                              TOTAL: ~130 Zeilen (nur Verkabelung)
```

### Was MINOR NEW CODE braucht (neue Datei <100L):
```
1. Credits via Gather-Tick:   gather_income_tick() +1 Credit/Planet                  ~10L
2. Building-Maintenance-Tick: EconomyManager liest BuildingDefinition.maintenance    ~30L
3. Dispatch-Undo:             WorkerTransport Cancel + Tween-Stop + Workers zurück   ~50L
4. Mobile Virtual Buttons:    D-Pad + Action-Buttons + Input.action_press()          ~150L
                              ─────────────────────────────────────
                              TOTAL: ~240 Zeilen (minor new code)
```

### Was NEUE SYSTEME braucht (neue Architektur):
```
1. Audio-Manager:             AudioManager + Trigger-Hookups + Asset-Imports         ~80L
2. Context-Hint Panel:        Milestone/Resource/Tech lesende Empfehlungs-Engine     ~80L
3. Sandbox Objectives:        Config + HUD-Element für verfolgbare Ziele             ~120L
                              ─────────────────────────────────────
                              TOTAL: ~280 Zeilen (new systems)
```

### Was als "funktional" markiert war, aber korrigiert werden muss:
```
❌ "Building-Maintenance funktioniert" → KORREKTUR: Nur Upgrade-Maintenance (via Traits)
   funktioniert. Building-Level-Maintenance (maintenance_resources) ist NICHT implementiert.

❌ "Credits via Trade-Tolls funktioniert" → KORREKTUR: API existiert, aber register_trade_route()
   wird NIE im Gameplay aufgerufen. Kein UI, kein Game-Logic. Trade-Routes sind ein Dead System.

❌ "Trade-Post Cost = 20V + 20C" → KORREKTUR: Trade-Post = 20 Volatile + 5 Credits
   (credit_cost default 5, kein Override in .tres)
```

---

## 3. KRITISCHSTE LÜCKEN (nach Verifizierung)

### P0 — Blockiert fundamentalen Spielspass
1. **Credits-Einkommen** — Gather-Tick gibt +1 Credit/Planet. ~10L Änderung in `gather_income_tick()`.
2. **Onboarding-Hint** — "Schicke dein Forschungsschiff zum Nachbarplaneten" nach 5s.

### P1 — Deutliche UX-Verbesserung
3. **Audio-System** — Ambient + 5 UI-Sounds. Neues System.
4. **Building-Complete Feedback** — `building_placed` → FloatingText. 5L Verkabelung.
5. **Mobile Virtual Buttons** — D-Pad + Action-Buttons. Neues System.
6. **Keyboard Shortcuts** — T=Tech, B=Workshop, Q=Close All. 20L Verkabelung.

### P2 — Progression-Tiefe
7. **Milestone-Belohnungen** — Credits/Resources bei First Scan/Ship/Colony. 20L Verkabelung.
8. **Building-Maintenance** — `maintenance_resources` abziehen. 30L Minor Code.
9. **CPU Personality** — 2-3 Presets. Neues System.
10. **Economy Dashboard** — Implementiert (`economy_window.gd`). Kein offener Code.

### P3 — Atmosphäre
11. **Camera-Shake** — Bei Battles. 15L Verkabelung.
12. **Discovery-Glow** — Tween auf Planet. 10L Verkabelung.
13. **Ship Trail Partikel** — CPUParticles2D. 30L Minor Code.
14. **Sector-Ownership-Overlay** — Farbliche Gebietsübersicht. 60L Minor Code.

---

## 4. GESAMT-AUFWAND

```
VERKABELUNG:        ~130 Zeilen  (10 Features, nur Signal→API)
MINOR NEW CODE:     ~240 Zeilen  (4 Features, kleine Dateien)
NEW SYSTEMS:        ~360 Zeilen  (4 Features, neue Architektur)
                    ──────────
GESAMT:             ~650 Zeilen  (19 Features)
```

**8 der 19 Features sind reine Verkabelung** — die Signale, Daten und APIs existieren bereits. Das Economy Dashboard ist inzwischen implementiert und entfällt als offenes Feature.

---

*Dieses Dokument ist verifiziert gegen den Code-Stand vom 2026-08-22.*
