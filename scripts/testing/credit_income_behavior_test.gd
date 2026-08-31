extends SceneTree

const ECONOMY_DOMAIN := preload("res://scripts/state/domains/economy_domain.gd")
const UPGRADE_CATALOG := preload("res://resources/config/planet_upgrade_catalog_default.tres")

func _initialize() -> void:
	var economy: EconomyDomain = ECONOMY_DOMAIN.new()
	economy.reset()
	economy.economy_config.credit_income_per_colony = 5
	economy.economy_config.credit_income_per_upgrade = 2
	economy.faction_credits[GameState.FACTION_PLAYER] = 0

	# Zwei Kolonien: eine ohne Upgrade, eine mit zwei Upgrades.
	# Ohne kumulativen Fehler: 5 + (5 + 2*2) = 14 Credits.
	economy.planet_upgrades[&"colony_a"] = []
	economy.planet_upgrades[&"colony_b"] = [&"extractor", &"refinery"]
	var earned: int = economy.credit_income_tick([&"colony_a", &"colony_b"], GameState.FACTION_PLAYER, UPGRADE_CATALOG)
	_assert_equal(earned, 14, "credit income is additive per colony")
	_assert_equal(economy.get_faction_credits(GameState.FACTION_PLAYER), 14, "credits are credited exactly once")

	# Zweiter Tick muss erneut exakt 14 gutschreiben, nicht den vorherigen
	# Fraktionswert mit einem Multiplikator vergrößern.
	var second: int = economy.credit_income_tick([&"colony_a", &"colony_b"], GameState.FACTION_PLAYER, UPGRADE_CATALOG)
	_assert_equal(second, 14, "second tick remains additive")
	_assert_equal(economy.get_faction_credits(GameState.FACTION_PLAYER), 28, "two ticks produce 28 credits")

	print("CREDIT_INCOME_BEHAVIOR: PASS")
	quit(0)

func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		push_error("CREDIT_INCOME_BEHAVIOR: FAIL %s (expected %s, got %s)" % [label, str(expected), str(actual)])
		quit(1)
