class_name UIStatusUtils
extends RefCounted

## Zentrale Status-Auflösung für Forschung und Bau: eine Quelle der Wahrheit
## für die Farbcodierung Grau (ungelernt/lernbar), Grün (gelernt),
## Rot (nicht lernbar) und Gelb (in Arbeit). Alle Views — Forschungsbaum-Dossier,
## Research-Views und Bau-Kacheln — lesen ihre Zustände ausschließlich hier.

const STATE_LEARNED := &"learned"
const STATE_IN_PROGRESS := &"in_progress"
const STATE_AVAILABLE := &"available"
const STATE_LOCKED := &"locked"

static func research_state(faction: StringName, technology: TechnologyDefinition, state: Node, catalog: TechnologyCatalog) -> StringName:
	if technology == null or state == null or catalog == null:
		return STATE_LOCKED
	if state.has_technology(faction, technology.id):
		return STATE_LEARNED
	if state.has_method(&"research_in_progress") and state.research_in_progress(faction, technology.id):
		return STATE_IN_PROGRESS
	if state.can_research_technology(faction, technology.id, catalog):
		return STATE_AVAILABLE
	return STATE_LOCKED

static func planet_research_state(own_planet: bool, researched: bool, in_progress: bool, can_research: bool) -> StringName:
	if researched:
		return STATE_LEARNED
	if in_progress:
		return STATE_IN_PROGRESS
	if not own_planet or not can_research:
		return STATE_LOCKED
	return STATE_AVAILABLE

static func upgrade_state(is_owned: bool, is_unlocked: bool, build_in_progress: bool, can_purchase_now: bool) -> StringName:
	if is_unlocked:
		return STATE_LEARNED
	if build_in_progress:
		return STATE_IN_PROGRESS
	if not is_owned or not can_purchase_now:
		return STATE_LOCKED
	return STATE_AVAILABLE

static func state_color(state_id: StringName, theme_config: UIThemeConfig = null) -> Color:
	var fallback_learned := Color(0.32, 0.88, 0.44)
	var fallback_available := Color(0.72, 0.76, 0.82)
	var fallback_locked := Color(1.0, 0.36, 0.31)
	var fallback_progress := Color(1.0, 0.78, 0.28)
	match state_id:
		STATE_LEARNED:
			return theme_config.status_learned_color if theme_config != null else fallback_learned
		STATE_IN_PROGRESS:
			return theme_config.status_in_progress_color if theme_config != null else fallback_progress
		STATE_AVAILABLE:
			return theme_config.status_available_color if theme_config != null else fallback_available
		_:
			return theme_config.status_locked_color if theme_config != null else fallback_locked

static func state_label(state_id: StringName) -> String:
	match state_id:
		STATE_LEARNED:
			return "GELERNT"
		STATE_IN_PROGRESS:
			return "IN ARBEIT"
		STATE_AVAILABLE:
			return "UNGERLERNT · LERNBAR"
		_:
			return "NOCH NICHT LERNBAR"

## Warum eine Technologie gesperrt ist: fehlende Voraussetzung oder fehlende
## Kosten. Leer, wenn nichts sperrt (Sprint-6-G7-Logik, zentralisiert).
static func locked_reason(technology: TechnologyDefinition, state: Node, catalog: TechnologyCatalog) -> String:
	if state == null or technology == null or state.can_research_technology(GameState.FACTION_PLAYER, technology.id, catalog):
		return ""
	var lines := ""
	if not String(technology.prerequisite_tech_id).is_empty() or not (technology.prerequisite_tech_ids as Array).is_empty():
		var missing_prereq: StringName = &""
		var candidates: Array[StringName] = []
		if not String(technology.prerequisite_tech_id).is_empty():
			candidates.append(technology.prerequisite_tech_id)
		elif not (technology.prerequisite_tech_ids as Array).is_empty():
			candidates.append_array(technology.prerequisite_tech_ids as Array)
		for prereq_id in candidates:
			if not state.has_technology(GameState.FACTION_PLAYER, prereq_id):
				missing_prereq = prereq_id
				break
		if not String(missing_prereq).is_empty() and catalog != null:
			var prereq: TechnologyDefinition = catalog.resolve(missing_prereq)
			lines = "\nVoraussetzung fehlt: %s" % (prereq.display_name if prereq != null else String(missing_prereq))
	var funds_ok := true
	if state.has_method("get_faction_resource") and int(state.get_faction_resource(GameState.FACTION_PLAYER, technology.cost_resource)) < technology.cost_amount:
		funds_ok = false
	if technology.credit_cost > 0 and state.has_method("get_faction_credits") and int(state.get_faction_credits(GameState.FACTION_PLAYER)) < technology.credit_cost:
		funds_ok = false
	if not funds_ok:
		lines += "\nRessourcen fehlen"
	return lines

## Live-Status der benötigten Technologie eines Baus/Gebäudes als Klartext.
static func required_tech_status(required_technology_id: StringName, state: Node, catalog: TechnologyCatalog) -> String:
	if state == null or catalog == null or String(required_technology_id).is_empty():
		return ""
	var technology: TechnologyDefinition = catalog.resolve(required_technology_id)
	if technology == null:
		return ""
	var research_state_id := research_state(GameState.FACTION_PLAYER, technology, state, catalog)
	match research_state_id:
		STATE_LEARNED:
			return "✓ Forschung abgeschlossen: %s" % technology.display_name
		STATE_IN_PROGRESS:
			var remaining: float = state.research_remaining(GameState.FACTION_PLAYER, technology.id)
			return "⟳ In Forschung: %s (%.0f s)" % [technology.display_name, remaining]
		_:
			var reason := locked_reason(technology, state, catalog).strip_edges()
			if reason.is_empty():
				return "✗ Erforderliche Forschung: %s" % technology.display_name
			return "✗ Erforderliche Forschung: %s%s" % [technology.display_name, reason.replace("\n", " · ")]

## Einheitlicher Mechanik-Effekttext einer TraitDefinition (Bau-Kontext).
static func trait_effect_text(trait_definition: TraitDefinition) -> Array[String]:
	var effects: Array[String] = []
	if trait_definition == null:
		return effects
	if trait_definition.production_boost > 0.0:
		effects.append("Produktion +%d%% pro Wirtschaftstick" % int(trait_definition.production_boost * 100.0))
	if trait_definition.worker_spawn_bonus > 0:
		effects.append("Einheiten-Nachschub +%d" % trait_definition.worker_spawn_bonus)
	if trait_definition.cluster_tier_bonus > 0:
		effects.append("Flotten-Tier +%d (stärkere Verbände)" % trait_definition.cluster_tier_bonus)
	if trait_definition.defense_rating > 0:
		effects.append("Planeten-Verteidigung +%d" % trait_definition.defense_rating)
	if trait_definition.perimeter_slots_bonus > 0:
		effects.append("Perimeter-Slots +%d (Verteidigungsring)" % trait_definition.perimeter_slots_bonus)
	if trait_definition.range_bonus > 0.0:
		effects.append("Verteidigungs-Reichweite +%.0f px" % trait_definition.range_bonus)
	if trait_definition.transfer_speed_multiplier > 1.0:
		effects.append("Transitgeschwindigkeit x%.1f (schnellerer Versand)" % trait_definition.transfer_speed_multiplier)
	if not String(trait_definition.maintenance_cost_resource).is_empty() and trait_definition.maintenance_cost_amount > 0:
		effects.append("Unterhalt: -%d %s pro Tick" % [trait_definition.maintenance_cost_amount, trait_definition.maintenance_cost_resource])
	return effects

## Kompakte Einzeilerversion von trait_effect_text.
static func trait_effect_summary(trait_definition: TraitDefinition) -> String:
	var effects := trait_effect_text(trait_definition)
	return "Mechanik: " + " · ".join(effects) if not effects.is_empty() else ""

## Formatierter Baufortschrittstext (Restzeit in Sekunden).
static func build_progress_text(remaining: float) -> String:
	if remaining >= 60.0:
		return "%.0f min %.0f s verbleibend" % [floorf(remaining / 60.0), fmod(remaining, 60.0)]
	return "%.0f s verbleibend" % remaining

## Fortschrittsprozent aus Gesamtzeit und Restzeit.
static func progress_percent(total_time: float, remaining: float) -> int:
	if total_time <= 0.0:
		return 100
	return int(round(clampf((total_time - remaining) / total_time, 0.0, 1.0) * 100.0))
