# SnipWar — Sprint 6: Onboarding & Early-Game Flow
**Erstellt:** 2026-08-24 · **Basis:** Playthrough-Audit + Entwickler-Feedback  
**Ziel:** Erste 5 Minuten zum Vergnügen machen — Steuerung klar, Start-Action, keine Blockaden

---

## 📊 SPRINT-ÜBERSICHT

| # | Story | Prio | Aufwand | Dateien |
|---|-------|------|---------|---------|
| S1 | Forschung braucht Dauer + Planeten-Indikator | 🔴 | M | tech_domain, planet.gd, tech_tree_view |
| S2 | Steuerungs-Tooltip + Hotkey-System | 🔴 | M | NEU: input_hint_overlay.gd, map_camera.gd |
| S3 | Gratis-Scout per Drag & Drop zu Planeten | 🔴 | L | scout_dispatch, worker_cluster, fleet_overview |
| S4 | Kamera-Start + FoV umschließt Startplaneten | 🔴 | S | map_camera.gd, world_config.gd |
| S5 | "Unbewohnte" Planeten + Nachbarschaft im FoV | 🟡 | M | planet.gd, planet_procedural.gd, game_state.gd |
| S6 | UI-Panel: Control-Felder mit fester Bounding-Box | 🟡 | XL | control_field.gd, layout_coordinator.gd, paper_dossier, economy, fleet, vault |
| S7 | PaperDossier CloseButton-Fix (Rotation) | 🟡 | S | paper_dossier.gd |
| S8 | Sub-Tabs im Dossier korrekt wechseln | 🟡 | S | planet_network_ui.gd / modal_coordinator.gd |
| S9 | Max 1 Auftrag pro Planet | 🟡 | S | worker_manager.gd, planet_panel.gd |

---

## 🔴 S1 — Forschung: Dauer & Indikator

### IST-Zustand
- `TechnologyDefinition.research_time` ist **durchgängig `0.0`** → instant
- `TechDomain.advance_research(delta)` existiert, wird aufgerufen, aber da `research_time=0` ist, passiert nichts
- `game_research_status` MCP-Tool zeigt `{active: [], completed: []}` weil `_research_jobs` leer

### SOLL
1. **Alle bestehenden Technologien auf `research_time` > 0 setzen:**
   - Tier-1: 15–20s (z.B. Werft-Design, Mech-Chassis)
   - Tier-2: 30–40s
   - Tier-3: 50–70s
2. **Forschung in Progress → `game_research_status` muss aktive Jobs zeigen** (Fix in `mcp_gameplay_tools.gd`)
3. **Planeten-Indikator:** `research_started`-Signal abfangen → Kreis/Ring über dem Planeten rendern
   - Neu: `research_indicator.gd` — kleiner Node2D (gepunkteter Ring), der bei `research_in_progress` sichtbar wird
   - Füllstand basierend auf `research_remaining() / research_time`
   - Position: über Planet-Sprite, `planet.gd` ergänzen um `add_research_indicator(tech_id, total_time)`

### Dateien
| Datei | Änderung |
|-------|----------|
| `resources/config/technology_catalog_default.tres` | Alle `research_time`-Werte setzen |
| `scripts/state/domains/tech_domain.gd` | `research_started`-Signal korrekt feuern |
| `scripts/objects/planets/planet.gd` | `_on_research_started()` Handler + Indicator |
| **NEU** `scripts/objects/planets/research_indicator.gd` | Visueller Ring-Node |
| `addons/gdscript_mcp/runtime/tools/gameplay/mcp_gameplay_tools.gd` | `_research_status()` liest korrekt aus |

---

## 🔴 S2 — Steuerungs-Tooltip + Hotkeys

### IST-Zustand
- Keine Tooltips, keine Hotkey-Anzeige, kein Tutorial
- Spieler weiß nicht: WASD/Edge-Scroll für Kamera, Mausrad-Zoom, ESC für Pause

### SOLL
1. **Neues `InputHintOverlay`** (CanvasLayer, Layer 85):
   - Rechts unten: 4–6 Hotkey-Chips mit Icon + Text, z.B.:
     - `[W A S D] Kamera bewegen`
     - `[ESC] Menü`
     - `[Mausrad] Zoomen`
     - `[Linksklick] Planet wählen`
     - `[Rechtsklick] Kontextmenü`
2. **Fade-Out nach 30s**, reappear bei neuem Kontext (z.B. erstes Mal Planet ausgewählt → zeige Dispatch-Hotkeys)
3. **Context-Trigger:**
   - `main_menu` → zeige keine Hints
   - `game_view` + kein Planet selektiert → zeige Basis-Steuerung
   - `game_view` + Planet selektiert → zeige `[M] Mission`, `[B] Bauen`, `[E] Einheiten`
4. **Jeder interaktive Button braucht einen Hotkey**:
   - `PLANET` → `P`
   - `WERKSTATT` → `W`
   - `FORSCHUNG` → `F`
   - `ECONOMY` → `E` (umbenennen zu `R` für Ressourcen?)
   - `SCHLIESSEN` → `ESC`
   - `BAUEN` → `Enter`

### Dateien
| Datei | Änderung |
|-------|----------|
| **NEU** `scripts/ui/input_hint_overlay.gd` | Tooltip-System |
| `scripts/backgrounds/map_camera.gd` | Hotkey-Tooltip-Trigger |
| `scripts/ui/dossier/paper_dossier.gd` | `ui_cancel` bestätigen + CloseButton-Hotkey |
| `scripts/objects/planets/planet_network_ui.gd` | Hotkeys für Sub-Tabs |
| `project.godot` | Neue Input-Map-Actions |

---

## 🔴 S3 — Gratis-Scout per Drag & Drop

### IST-Zustand
- VISION.md: "Der Scout bleibt der kostenlose Start-Scout"
- Keine Implementierung eines initialen Scout-Schiffs
- `FleetOverview` hat bereits Drag-to-Dispatch

### SOLL
1. **Beim Spielstart 1 Scout-Schiff gratis spawnen** (auf Spieler-Homeworld)
   - `GameState`/`ShipDomain`: `add_free_scout(planet_id)`
   - Schiff erscheint in FleetOverview und ist per Drag & Drop zuweisbar
2. **Drag & Drop auf Planeten:**
   - `FleetOverview`-Drag nutzen — Ziel-Planet highlighten beim Hovern
   - Drop = automatischer Dispatch (Scout-Mission)
3. **Scout-Ergebnis nach Ankunft:** Planet wird "erkundet" (Ressourcen, Größe sichtbar)

### Dateien
| Datei | Änderung |
|-------|----------|
| `scripts/state/domains/ship_domain.gd` | `add_free_scout()` Methode |
| `scripts/state/game_state.gd` | `create_starting_scout()` in World-Init |
| `scripts/ui/fleet_overview.gd` | Drag-Ziel-Highlight auf Planeten |
| `scripts/objects/planet_view.gd` | Drop-Target Registrierung |
| `scripts/objects/planets/planet.gd` | Scout-Ankunft-Handler |

---

## 🔴 S4 — Kamera-Start: FoV zeigt Nachbarschaft

### IST-Zustand
- Kamera startet bei `(-6663, -6873)` — Spieler sieht **leeren Weltraum**
- Spieler muss manuell pannen, um erste Planeten zu finden

### SOLL
1. **Kamera auf Spieler-Homeworld zentrieren** beim World-Start
   - `MapCamera` oder `WorldBootstrap`: `position = homeworld_planet.global_position`
2. **Initial-Zoom so setzen, dass 3–5 nächste Nachbarplaneten sichtbar sind**
   - Berechnung: min/max der nächsten 5 Planet-Positionen → Zoom-Faktor
3. **Sanfter Easing-Tween** zum Ziel (1.5s) — nicht hart springen
4. **Min-Zoom / Max-Zoom in `map_camera.gd`** bereits definiert (`min_zoom=1, max_zoom=2.5`)

### Dateien
| Datei | Änderung |
|-------|----------|
| `scripts/backgrounds/map_camera.gd` | `center_on(homeworld_pos, zoom)` Methode |
| `scripts/world_bootstrap.gd` | Kamera-Zentrierung nach World-Generation |

---

## 🟡 S5 — "Unbewohnte" Planeten + Typ-Differenzierung

### IST-Zustand
- `FACTION_NEUTRAL = "neutral"` — keine Unterscheidung zwischen "neutral" und "unbewohnt"
- Alle nicht-eroberten Planeten sind `neutral`

### SOLL
1. **Neue Faction-Konstante:** `FACTION_UNINHABITED = "uninhabited"`  
2. **`PlanetProcedural`/`SeededLayout`:** ~30% der Planeten als `uninhabited` markieren
   - Keine Garnison, keine Arbeiter, keine Gebäude
   - Andere visuelle Darstellung (grau/blass oder nur Silhouette)
3. **"Unbewohnte" Planeten sind kolonisierbar** → `MISSION_COLONY`
4. **Direkte Nachbarschaft** (5 nächste Planeten) zu Spielstart garantiert gemischt:
   - 1× unbewohnt (für Kolonie-Tutorial)
   - 3× neutral
   - 1× CPU-nah

### Dateien
| Datei | Änderung |
|-------|----------|
| `scripts/state/game_state.gd` | `FACTION_UNINHABITED` Konstante |
| `scripts/objects/planets/procedural/planet_procedural.gd` | `uninhabited`-Flag + visuelle Behandlung |
| `scripts/config/seeded_layout.gd` | Verteilungslogik |
| `scripts/objects/planets/planet.gd` | `is_uninhabited()` Methode |

---

## 🟡 S6 — UI-Panel: Feste Control-Felder & Panel-Zonen

### IST-Zustand
- Planet-Dossier (PaperDossier, CanvasLayer 80), Economy (Control, floating), FleetOverview (Control, rechts)
- Überlappen sich, kein fixes Layout — PaperDossier ist Fullscreen und verdeckt alles
- Jedes Panel baut eigene Container, aber kein gemeinsames Koordinatensystem
- FleetOverview hat bereits Rechts-Andockung aber keine feste Bounding-Box
- "Control-Felder"-Konzept fehlt komplett: Panel-Inhalte fließen frei ohne abgegrenzte Canvas-Bereiche

### SOLL

#### A — `ControlField` Basisklasse (NEU)
Ein **ControlField** ist ein `Control`-Node mit fest definierter Bounding-Box, die sich nie mit anderen Feldern überlappt:

```gdscript
class_name ControlField
extends Control

## Jedes Panel bekommt ein ControlField — eine feste, nicht-überlappende
## Bounding-Box die bei Viewport-Resize skaliert, aber nie andere Felder schneidet.

@export var field_id: StringName = &""
@export var anchor_left: float = 0.0
@export var anchor_top: float = 0.0  
@export var width_ratio: float = 0.35
@export var height_ratio: float = 0.85
@export var min_width: int = 280
@export var max_width: int = 520
```

#### B — Panel-Zonen (5 Control Fields)

| Field | Anchor | Größe | Inhalt |
|-------|--------|-------|--------|
| `field_map` | (0,0) → (1,1) | 100%×100% | Karte + HUD (kein Panel overlay erlaubt) |
| `field_dossier_left` | (0, 0.08) | 36%×85% | Planet-Dossier / Forschung / Werkstatt |
| `field_fleet_right_top` | (0.62, 0.08) | 36%×40% | FleetOverview |
| `field_economy_right_bottom` | (0.62, 0.55) | 36%×40% | EconomyWindow (Ressourcen) |
| `field_vault_top` | (0.36, 0) | 26%×6% | VaultBar (Credits, immer sichtbar) |

```
┌────────────────────────────────────────────────────┐
│ [PLANETEN ›] [TECHNOLOGIE ›]    VAULTBAR           │  ← field_vault_top
│                 ║                                  │
│  DOSSIER        ║         MAP                     │
│  (Planet /      ║    (kein Overlay!)              │
│   Forschung /   ║                                  │
│   Werkstatt)    ║                                  │
│                 ║                                  │
│  36% Breite     ║                                  │
│                 ╠══════════════════════════════════ │
│                 ║  FLEET OVERVIEW                  │
│                 ║  (Schiffe, Planeten)             │
│                 ╠══════════════════════════════════ │
│                 ║  ECONOMY (Ressourcen)            │
└────────────────────────────────────────────────────┘
```

#### C — ControlField-Regeln
1. **Kein ControlField darf ein anderes überlappen** — `LayoutCoordinator` berechnet Bounds
2. **Viewport-Resize** → alle Fields skalieren proportional, halten `min_width`/`max_width`
3. **`field_map` ist durchlässig:** Planet-Klicks gehen durch (mouse_filter = IGNORE)
4. **`field_dossier_left`** hostet `PaperDossier` (nicht mehr Fullscreen)
5. **`field_fleet_right_top`** hostet `FleetOverview` (Drag & Drop funktioniert nur innerhalb)
6. **`field_economy_right_bottom`** hostet `EconomyWindow` (statt Floating-Overlay)
7. **`field_vault_top`** hostet `VaultBar` (Credits + Einkommen)

#### D — Responsive Collapse
- Bei Viewport < 1024px breit: Dossier + Fleet klappen zu Tab-Leiste zusammen (Mobile-Fallback)
- `ControlField` hat `collapse_on_narrow: bool = true`

### Dateien
| Datei | Änderung |
|-------|----------|
| **NEU** `scripts/ui/control_field.gd` | Basisklasse für alle Panel-Bereiche |
| **NEU** `scripts/ui/layout_coordinator.gd` | Verwaltet alle ControlFields, berechnet Bounds, verhindert Überlappung |
| `scripts/ui/dossier/paper_dossier.gd` | Nicht mehr Fullscreen → als Child von `field_dossier_left` |
| `scripts/ui/dossier/modal_coordinator.gd` | Koordiniert mit LayoutCoordinator statt direktem Fullscreen |
| `scripts/objects/planets/planet_network_ui.gd` | Panel-Zonen via LayoutCoordinator registrieren |
| `scripts/ui/economy_window.gd` | Kein eigenes Floating mehr → als Child von `field_economy_right_bottom` |
| `scripts/ui/fleet_overview.gd` | In `field_fleet_right_top` einbetten, Drag-Bounds respektieren |
| `scripts/ui/vault_bar.gd` | In `field_vault_top` fixieren |

---

## 🐛 S7 — PaperDossier CloseButton-Fix

### IST-Zustand
- CloseButton klickbar, aber Sheet-Rotation `-1.1°` verschiebt Button-Position
- `runtime_ux_find` match_score nur 0.75
- Manche Klicks gehen ins Leere

### Fix
- Sheet-Rotation auf `0°` reduzieren ODER CloseButton außerhalb der Rotation platzieren
- Oder: `_unhandled_input` ESC-Handler bereits vorhanden → Tastatur-Close funktioniert, nur Maus-Close ist betroffen
- Einfachster Fix: Rotation entfernen (`_set_open` → `_sheet.rotation = 0`)

### Dateien
| Datei | Änderung |
|-------|----------|
| `scripts/ui/dossier/paper_dossier.gd` | Rotation entfernen oder CloseButton separat positionieren |

---

## 🐛 S8 — Sub-Tabs im Dossier korrekt wechseln

### IST-Zustand
- PLANET/WERKSTATT/FORSCHUNG/ECONOMY als Buttons im Dossier
- `runtime_ux_click` feuert korrekt, aber Content ändert sich nicht

### Fix
- Debuggen via `planet_network_ui.gd` → Tab-Click-Handler prüfen
- `_replace_content()` wird nicht aufgerufen oder Tab-Index-Mapping ist falsch

### Dateien
| Datei | Änderung |
|-------|----------|
| `scripts/objects/planets/planet_network_ui.gd` | Tab-Switch-Logik reparieren |

---

## 🐛 S9 — Max 1 Auftrag pro Planet

### IST-Zustand
- Kein Limit für parallele Dispatch-Aufträge auf denselben Planeten

### SOLL
- `WorkerManager` / `PlanetPanel`: Wenn bereits ein Auftrag für Planet X läuft, "Ziel auswählen"-Button disablen mit Hinweis: "Bereits ein Auftrag aktiv"

### Dateien
| Datei | Änderung |
|-------|----------|
| `scripts/objects/worker_manager.gd` | `has_active_order(planet_id)` → Check vor Dispatch |
| `scripts/objects/planets/planet_network_ui.gd` | UI-Disable bei aktivem Auftrag |

---

## 📅 SPRINT-REIHENFOLGE

```
Tag 1: S7 (CloseButton) → S8 (Sub-Tabs) → S4 (Kamera-Start)
Tag 2: S1 (Forschung Dauer + Indikator)
Tag 3: S2 (Tooltip + Hotkeys)
Tag 4: S3 (Gratis-Scout Drag & Drop)
Tag 5: S5 (Unbewohnte Planeten) → S9 (1 Auftrag/Planet)
Tag 6–7: S6 (Control-Felder + Panel-Zonen) — größte UI-Refaktor
Tag 8: Polishing + MCP-Playthrough-Test aller Stories
```

## 📦 ATOMARE COMMIT-GRUPPEN

| Commit | Dateien |
|--------|---------|
| `fix: dossier close-button and sub-tab switching` | `paper_dossier.gd`, `planet_network_ui.gd`, `modal_coordinator.gd` |
| `feat: camera starts centered on homeworld with neighbor FoV` | `map_camera.gd`, `world_bootstrap.gd` |
| `feat: timed research with planet indicator rings` | `tech_domain.gd`, `technology_catalog_default.tres`, `planet.gd`, `research_indicator.gd`, `mcp_gameplay_tools.gd` |
| `feat: input hint overlay with hotkey context system` | `input_hint_overlay.gd`, `map_camera.gd`, `paper_dossier.gd`, `planet_network_ui.gd`, `project.godot` |
| `feat: free starter scout ship with drag-and-drop dispatch` | `ship_domain.gd`, `game_state.gd`, `fleet_overview.gd`, `planet_view.gd`, `planet.gd` |
| `feat: uninhabited planet type and starting neighborhood mix` | `game_state.gd`, `planet_procedural.gd`, `planet.gd`, `seeded_layout.gd` |
| `feat: control-field panel zones — non-overlapping layout with left dossier, right fleet+economy` | `control_field.gd`, `layout_coordinator.gd`, `paper_dossier.gd`, `modal_coordinator.gd`, `planet_network_ui.gd`, `economy_window.gd`, `fleet_overview.gd`, `vault_bar.gd` |
| `feat: max one active dispatch order per planet` | `worker_manager.gd`, `planet_network_ui.gd` |