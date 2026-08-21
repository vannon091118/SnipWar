# Graphical Assets Plan: World Gen & Ship Builder Building Blocks

## Overview
Create a comprehensive set of SVG assets in **comic paper clip style** for:
- World generation (planet variations, decals, details)
- Ship building (hull variants, component variants, modules)
- Upgrade visualizations (planet upgrade structures)
- Menu backgrounds

All work to be done on a new branch `feature/graphical-assets`.

---

## Branch Setup
```bash
git checkout -b feature/graphical-assets
```

---

## Asset Categories & Requirements

### 1. Planet Variations (World Gen)
**Current:** 10 base planets (ember, ice, violet, desert, toxic, storm, volcanic, golden, ocean, paper)
**Needed:** **3 variations per planet type** = **30 new planet SVGs** (confirmed)

**Naming:** `assets/objects/planets/planet_XX_<type>_v<variant>.svg`
- `planet_01_ember_v2.svg`, `planet_01_ember_v3.svg`, `planet_01_ember_v4.svg`
- Same pattern for all 10 types

**Style constraints:**
- ViewBox: 256×256 (matching existing)
- Dark outline stroke (#080b14 / #090b16, 6-8px)
- Base fill + 3-4 detail layers with color variation
- Small accent circles/dots for texture
- Consistent "paper clip" aesthetic: bold shapes, limited palette per planet

**Technical:** Used by `PlanetDefinition.visual_asset` / `composition_base_texture` for procedural composition.

---

### 2. Planet Decals (Procedural Composition)
**Current:** None (referenced in `WorldConfig.composition_decal_pool`)
**Needed:** **15-20 decal SVGs** for procedural planet composition

**Categories:**
- **Surface features (6-8):** crater_field, fissure_network, ridge_chain, dune_pattern, ice_cracks, lava_flows, spore_patches, crystal_veins
- **Atmospheric (4-5):** storm_bands, aurora_arcs, haze_layers, cloud_streaks, polar_caps
- **Artificial (4-5):** city_lights, orbital_ring, launch_pads, sensor_arrays, defense_grid

**Naming:** `assets/objects/planets/decals/decal_<name>.svg`
**ViewBox:** 256×256 (overlay scale)
**Style:** Semi-transparent overlays, single-color with alpha, no stroke or very thin stroke

**Technique:** Applied via `compose_planet()` in `world_generator.gd` using `composition_tint`.

---

### 3. Planet Detail Objects (Orbiting Details)
**Current:** satellite (planet_satellite.svg), asteroid_belt, comet (reuse navigation assets)
**Needed:** **8-10 new detail SVGs** for `PlanetDetailFidelity` variations

**Types needed:**
- **Debris ring variants (3):** thin_ring, thick_ring, segmented_ring
- **Orbital stations (2):** research_station, military_outpost
- **Moon variants (2):** moon_barren, moon_ice
- **Anomaly (1):** wormhole_marker
- **Industrial (2):** mining_platform, refinery_complex

**Naming:** `assets/objects/planets/details/detail_<name>.svg`
**ViewBox:** 128×128 or 256×256 depending on orbit distance
**Style:** Smaller scale, simpler shapes, distinct silhouettes

**Technique:** Referenced by `PlanetDetailDefinition.visual_asset`, spawned by `PlanetDetails.add_upgrade_structure()` / detail system.

---

### 4. Ship Hull Variants (Ship Builder)
**Current:** 3 hulls (cluster_k.svg T1, cluster_m.svg T2, cluster_l.svg T3 - but T3 reuses cluster_l)
**Needed:** **9 hull variants** (3 per tier, visually distinct)

**Tier 1 (Scout/Light):** 3 variants
- `hull_t1_scout.svg` (current cluster_k - needle shape)
- `hull_t1_interceptor.svg` (delta wing)
- `hull_t1_courier.svg` (elongated with nacelles)

**Tier 2 (Medium):** 3 variants
- `hull_t2_multirole.svg` (current cluster_m - triad)
- `hull_t2_carrier.svg` (flat with launch bays)
- `hull_t2_destroyer.svg` (angular, weapon hardpoints visible)

**Tier 3 (Heavy):** 3 variants (iterate on cluster_l.svg base with modular addons)
- `hull_t3_expansion.svg` (cluster_l + habitat ring addon)
- `hull_t3_dreadnought.svg` (cluster_l + armor plating + weapon pods)
- `hull_t3_colony.svg` (cluster_l + dual habitat rings)

**Naming:** `assets/objects/ships/hulls/hull_<tier>_<name>.svg`
**ViewBox:** 96×96 (T1), 128×128 (T2), 160×160 (T3)
**Style:** Cell-shaded mech silhouette, distinct profile per role, attachment points marked visually

**Technique:** Referenced by `ShipPartDefinition.visual_asset` for hull parts. Variant selection via `ShipBlueprint.seed_base` + `instance_seed`.

---

### 5. Ship Component Variants (Visual Overlays)
**Current:** Limited variants (drive_fast/stable, weapon_precision/burst, shield_lattice/reactive)
**Needed:** **2-3 visual variants per component type per tier**

**Component types:**
- **Drives (6):** T1: ion_blue, ion_green, plasma_red | T2: grav_blue, grav_purple, warp_gold
- **Weapons (6):** T1: pulse, beam, projectile | T2: plasma, railgun, missile
- **Shields (6):** T1: bubble, lattice, reactive | T2: phase, harmonic, ablative
- **Scanners (4):** T1: dish, array | T2: phased, quantum
- **Modules/Utility (8):** armor, fuel, cargo, reactor, reinforced, sensor, ecm, repair

**Naming:** `assets/objects/ships/components/<slot>_<tier>_<variant>.svg`
**ViewBox:** 64×64 (overlays scale via `TransformerConfig` scales)
**Style:** Modular "kitbash" aesthetic - distinct shapes that composite cleanly on hulls

**Technique:** Referenced by `ShipComponentVariant.visual_asset`. CompositeShipView applies `ship_*_offset/scale` from `TransformerConfig`.

---

### 6. Upgrade Structure Visuals (Planet Upgrades)
**Current:** 18 upgrades sharing ~5 assets (cluster_m, planet_satellite, meteors, structures)
**Needed:** **Unique visual per upgrade (18 SVGs)** + variations for tier progression

**Upgrades needing unique visuals:**
| Upgrade | Current Asset | New Asset |
|---------|---------------|-----------|
| extractor | meteor_03_metal | structure_extractor.svg |
| refinery | meteor_03_metal | structure_refinery.svg |
| trade_post | trade_hub | structure_trade_post.svg |
| shipyard | cluster_m | structure_shipyard.svg |
| war_shipyard | cluster_m | structure_war_shipyard.svg |
| colony_shipyard | cluster_m | structure_colony_shipyard.svg |
| defense_grid | cluster_m | structure_defense_grid.svg |
| tech_center | planet_satellite | structure_tech_center.svg |
| weapon_lab | planet_satellite | structure_weapon_lab.svg |
| armor_lab | planet_satellite | structure_armor_lab.svg |
| orbital_station | planet_satellite | structure_orbital_station.svg |
| colony_hub | planet_satellite | structure_colony_hub.svg |
| trade_network | trade_hub | structure_trade_network.svg |
| automated_mine | automated_mine | structure_automated_mine_v2.svg |
| trade_hub | trade_hub | structure_trade_hub_v2.svg |
| comms_array | comms_array | structure_comms_array.svg |
| deep_space_scanner | planet_satellite | structure_deep_space_scanner.svg |

**Naming:** `assets/objects/structures/structure_<id>.svg`
**ViewBox:** 128×96 (matching automated_mine)
**Style:** Ground-based structures, isometric-ish, faction-tintable via `TransformerConfig` tints
**Variations:** Each gets **3 "level" variants (L1, L2, L3)** for visual progression = **54 structure SVGs** (confirmed)

**Technique:** Referenced by `PlanetUpgradeDefinition.visual_asset`. `PlanetDetails.add_upgrade_structure()` creates `UpgradeStructure_<id>` children with orbit params from `TransformerConfig`.

---

### 7. Menu Backgrounds
**Current:** Only starfield background (procedural), snipwar_banner.jpg
**Needed:** **5-6 menu background SVGs** for UI panels

**Types:**
- `ui_bg_main_menu.svg` - Full screen, atmospheric
- `ui_bg_tech_menu.svg` - Side panel compatible, tech aesthetic
- `ui_bg_ship_hangar.svg` - Hangar bay interior
- `ui_bg_planet_panel.svg` - Subtle, non-distracting
- `ui_bg_pause_menu.svg` - Semi-transparent overlay
- `ui_bg_modal.svg` - Generic modal backdrop

**Naming:** `assets/ui/backgrounds/ui_bg_<name>.svg`
**ViewBox:** 1920×1080 (scales down)
**Style:** Subtle paper texture, fold lines, muted palette matching `UIThemeConfig` colors
**Technique:** Used as `TextureRect` backgrounds in UI scenes, or `StyleBoxTexture` for panels.

---

## Implementation Order

### Phase 1: Foundation (Week 1)
1. Create branch & directory structure
2. Planet variations (10 types × 3 variants = **30 SVGs**)
3. Planet decals (15 SVGs in new `decals/` subfolder)

### Phase 2: Details & Structures (Week 2)
4. Planet detail objects (10 SVGs in new `details/` subfolder)
5. Upgrade structures (18 base + 36 level variants = 54 SVGs)

### Phase 3: Ship Builder Assets (Week 3)
6. Hull variants (9 SVGs in new `hulls/` subfolder)
7. Component variants (~30 SVGs in new `components/` subfolder)

### Phase 4: UI Backgrounds (Week 4)
8. Menu backgrounds (6 SVGs in `assets/ui/backgrounds/`)
9. Update `.tres` configs to reference new assets
10. Run preflight to validate

---

## Directory Structure Changes

```
assets/
├── objects/
│   ├── planets/
│   │   ├── decals/           # NEW
│   │   ├── details/          # NEW
│   │   └── (existing planet_*.svg)
│   ├── ships/
│   │   ├── hulls/            # NEW
│   │   ├── components/       # NEW
│   │   └── (existing ship_*.svg)
│   ├── structures/           # EXPAND (add 54 SVGs)
│   ├── workers/              # (existing)
│   ├── satellites/           # (existing)
│   ├── navigation/           # (existing)
│   └── meteors/              # (existing)
├── ui/
│   ├── backgrounds/          # NEW
│   └── (existing)
└── backgrounds/              # (existing nebula .tres)
```

---

## Config Updates Required

### Planet Catalog (`resources/config/planet_catalog.tres`)
- Add `composition_decal_pool` entries referencing new decals
- Update planet definitions with variation references

### Ship Part Catalog (`resources/config/ship_part_catalog_default.tres`)
- Add new hull parts (hull_t1_interceptor, hull_t1_courier, hull_t2_carrier, etc.)
- Add new component variants for each slot/tier
- Update `visual_asset` paths

### Planet Upgrade Catalog (`resources/config/planet_upgrade_catalog_default.tres`)
- Update each upgrade's `visual_asset` to new structure SVGs
- Add level progression references

### UI Theme (`resources/config/ui_theme_default.tres`)
- Add background texture references for panels

### Technology Catalog (`resources/config/technology_catalog_default.tres`)
- Update tech `visual_asset` where appropriate (e.g., new hull visuals)

---

## Validation Checklist

- [ ] All SVGs valid (xmlns, viewBox, no external refs)
- [ ] Consistent stroke width (3-8px) and color (#080b14)
- [ ] Palette matches comic paper clip style
- [ ] Assets import without errors (Godot headless)
- [ ] Preflight passes: `godot --headless --path . --script res://scripts/preflight.gd`
- [ ] Smoke test passes: `godot --headless --path . --quit-after 2`
- [ ] No duplicate UIDs in .tres files (use path-only refs)
- [ ] Git diff shows only new assets + config updates

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Asset count too large for single PR | Split into 3-4 PRs by phase |
| Visual inconsistency across artists | Single style guide + reference sheets |
| Config paths break | Use relative `res://` paths, validate with preflight |
| Godot re-saves .tres on headless run | Check `git status` after preflight, revert spurious changes |
| Import UIDs change | Commit `.import` sidecars with SVGs |

---

## Resolved Decisions

1. **Variant count per planet:** 3 variations per type (30 total) ✓
2. **Upgrade structure levels:** 3 levels per upgrade (L1/L2/L3) = 54 SVGs ✓
3. **Menu background approach:** SVG textures matching comic paper clip style ✓
4. **Ship hull T3:** Iterate on cluster_l.svg with modular addons ✓

---

## Next Steps

1. Create branch `feature/graphical-assets`
2. Create directory structure per plan
3. Begin Phase 1 implementation (planet variations + decals)