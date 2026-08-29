extends SceneTree

## E1-Gate (R-007): Verifiziert die Referenzsemantik und Signal-Identität der
## EconomyVaultCore-Delegation.
##   1. Direkte Dict-Pokes (Preflight-Stil) sind in der Unit sichtbar.
##   2. Unit-Mutationen erzeugen dieselben Signal-Emissionen (GameState-Verbindungen).
##   3. Save-Roundtrip über die Fassade ersetzt die Dicts, ohne die Unit zu
##      entkoppeln (Unit liest weiterhin über _owner).
## Exit 1 bei Abweichung — echte Assertions, kein Print-only.

var _failures: Array[String] = []


func _init() -> void:
	# Deferred: GameState-Autoload ist im --script-Modus verfügbar, aber wir
	# warten einen Frame, damit die Domänen-Verdrahtung stabil ist.
	call_deferred("_run")


func _run() -> void:
	var economy: EconomyDomain = EconomyDomain.new()

	# --- 1. Referenzsemantik: direkter Poke ist in der Unit sichtbar ---
	economy.faction_vaults[GameState.FACTION_PLAYER] = {GameState.RES_ENERGY: 10}
	var seen_by_unit: int = economy.get_faction_resource(GameState.FACTION_PLAYER, GameState.RES_ENERGY)
	if seen_by_unit != 10:
		_failures.append("direct dict poke not visible to unit (got %d)" % seen_by_unit)

	# --- 2. Unit-Mutation emittiert das Fassaden-Signal ---
	var emissions: Array = []
	economy.faction_resources_changed.connect(func(faction: StringName, res: StringName, amount: int) -> void:
		emissions.append([faction, res, amount])
	)
	economy.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_ENERGY, 5)
	if emissions.size() != 1:
		_failures.append("expected 1 faction_resources_changed emission, got %d" % emissions.size())
	elif int(emissions[0][2]) != 15:
		_failures.append("expected emitted amount 15, got %d" % int(emissions[0][2]))

	# --- 3. Credits-Signal über die Unit ---
	var credit_emissions: Array = []
	economy.credits_changed.connect(func(faction: StringName, amount: int) -> void:
		credit_emissions.append([faction, amount])
	)
	economy.add_faction_credits(GameState.FACTION_PLAYER, 7)
	if credit_emissions.size() != 1 or int(credit_emissions[0][1]) != 7:
		_failures.append("credits_changed emission via unit wrong: %s" % str(credit_emissions))

	# --- 4. reset() über die Unit leert die Fassaden-Dicts ---
	economy.add_faction_resource(GameState.FACTION_CPU, GameState.RES_BIOMASS, 3)
	economy.reset()
	if not economy.faction_vaults.get(GameState.FACTION_PLAYER, {}).get(GameState.RES_ENERGY, 0) == 50:
		_failures.append("reset_vaults did not restore 50 energy")
	if not economy.planet_resources.is_empty() or not economy.worker_reservations.is_empty():
		_failures.append("reset() did not clear facade dicts")

	# --- 5. Local-Vault-Referenzsemantik ---
	economy.set_planet_resource(&"p1", GameState.RES_ENERGY)
	economy.seed_local_resources([&"p1"], null, 42)
	var seeded: int = economy.get_local_resource(&"p1", GameState.RES_ENERGY)
	if seeded <= 0:
		_failures.append("seed_local_resources produced no stock (got %d)" % seeded)
	var vault_ref: Dictionary = economy.local_vault(&"p1")
	vault_ref[GameState.RES_ENERGY] = 99
	if economy.get_local_resource(&"p1", GameState.RES_ENERGY) != 99:
		_failures.append("local_vault reference semantics broken")

	# --- 6. Snapshot/Restore ersetzt Dicts; Unit bleibt gekoppelt ---
	var data := RunSaveData.new()
	economy.capture_snapshot(data)
	var probe: EconomyDomain = EconomyDomain.new()
	probe.restore_snapshot(data)
	if probe.get_local_resource(&"p1", GameState.RES_ENERGY) != 99:
		_failures.append("snapshot/restore roundtrip lost local vault state")
	if probe.get_faction_resource(GameState.FACTION_PLAYER, GameState.RES_ENERGY) != 50:
		_failures.append("snapshot/restore roundtrip lost faction vault state")

	# --- 7. Worker-Reservierungen über die Unit ---
	if not economy.reserve_workers(&"p1", &"job_a", 2, 5):
		_failures.append("reserve_workers failed")
	if economy.available_workers(&"p1", 5) != 3:
		_failures.append("available_workers wrong after reservation")
	if economy.release_workers(&"p1", &"job_a") != 2:
		_failures.append("release_workers returned wrong amount")

	if not _failures.is_empty():
		for failure in _failures:
			printerr("[E1-FAIL] " + failure)
		print("E1 VAULT-CORE SEMANTICS: FAIL (%d failures)" % _failures.size())
		quit(1)
		return
	print("E1 VAULT-CORE SEMANTICS: PASS (7/7 checks)")
	quit(0)
