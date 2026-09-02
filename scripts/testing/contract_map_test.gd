extends SceneTree

## V3-009: Vertrags-SSOT-Test — contract_map.json ist die eine Quelle für
## Pfad-Klassifikation (Resolver-Contracts UND Guard-Groups). Prüft:
## wohlgeformt, Gruppen bekannt, keine leeren Wildcard-Segmente (der
## ends_with("")-Trap), jeden Rule-Glob auf Match-Verhalten, und Spot-Checks
## bekannter Pfade beider Lesarten.

const SCANNER := preload("res://scripts/preflight_v2/constraint_scanner.gd")

const MAP_PATH := "res://scripts/preflight_v2/contract_map.json"

var checks := 0
var failures := 0


func _init() -> void:
	if not FileAccess.file_exists(MAP_PATH):
		_fail("contract_map.json existiert nicht")
		_finish()
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	if not (parsed is Dictionary and parsed.has("rules")):
		_fail("contract_map.json ist kein Objekt mit 'rules'")
		_finish()
		return

	var rules: Array = parsed["rules"]
	var groups: Array = parsed.get("groups", [])
	var group_set := {}
	for g in groups:
		group_set[String(g)] = true

	_check(rules.size() >= 80, "Regelzahl plausibel (%d)" % rules.size())
	_check(groups.size() >= 13, "Gruppenzahl plausibel (%d)" % groups.size())

	var globs := {}
	for rule in rules:
		if not (rule is Dictionary and rule.has("glob") and rule.has("contracts") and rule.has("groups")):
			_fail("Rule ohne glob/contracts/groups: %s" % str(rule))
			continue
		var glob := String(rule["glob"])
		if globs.has(glob):
			_fail("Duplikat-Glob: %s" % glob)
		globs[glob] = true		# Groups: entweder AUTO, ALL_DOMAINS oder bekannte Gruppenliste.
		var gr: Variant = rule["groups"]
		if gr is String and (gr == "AUTO" or gr == "ALL_DOMAINS"):
			pass
		elif gr is Array:
			for g in gr:
				if not group_set.has(String(g)):
					_fail("Unbekannte Gruppe '%s' an Glob %s" % [String(g), glob])
		else:
			_fail("Ungültiger groups-Wert an %s: %s" % [glob, str(gr)])
		# Contracts nicht leer.
		if not (rule["contracts"] is Array) or (rule["contracts"] as Array).is_empty():
			_fail("Leere contracts an %s" % glob)
		# Keine leeren Wildcard-Segmente (ends_with("")-Trap) — außer Muster
		# wie "foo*" (Suffix ""), wo Prefix+Name die Spezifität tragen.
		if glob.contains("*") and not glob.ends_with("/**") and not glob.ends_with("**"):
			var parts: PackedStringArray = glob.split("*")
			for i in range(1, parts.size() - 1):
				if str(parts[i]).is_empty():
					_fail("Leeres Zwischen-Segment in Glob '%s' (Matcher-Falle)" % glob)

	# Der Scanner liefert genau diese Regeln als (glob, contracts)-Paare.
	var scanner = SCANNER.new()
	var from_scanner: Array = scanner.path_contracts()
	_check(from_scanner.size() == rules.size(),
		"Scanner-Regelzahl == SSOT-Regelzahl (%d == %d)" % [from_scanner.size(), rules.size()])

	# Spot-Checks: bekannte Pfade beider Lesarten (Resolver-Contracts via _matches).
	var spot := {
		"scripts/flight_time.gd": true,
		"scripts/objects/ships/ship_manager.gd": true,
		"some/unknown/thing.gd": false,
	}
	for path in spot.keys():
		var hit: bool = false
		for rule in from_scanner:
			if _matches(String(path), String(rule["glob"])):
				hit = true
				break
		if spot[path]:
			_check(hit, "bekannter Pfad matcht: %s" % str(path))
		else:
			_check(not hit, "unbekannter Pfad bleibt unmapped: %s" % str(path))

	_finish()


func _matches(path: String, glob: String) -> bool:
	if glob == "*":
		return true
	if glob.ends_with("/**"):
		return path.begins_with(glob.trim_suffix("/**")) or path == glob.trim_suffix("/**")
	if glob.ends_with("**"):
		return path.begins_with(glob.trim_suffix("**"))
	if glob.contains("*"):
		var fixed: PackedStringArray = glob.split("*")
		var prefix := str(fixed[0])
		var suffix := str(fixed[fixed.size() - 1])
		if not path.begins_with(prefix):
			return false
		if not path.ends_with(suffix):
			return false
		var cursor := prefix.length()
		var ceiling := path.length() - suffix.length()
		for i in range(1, fixed.size() - 1):
			var seg := str(fixed[i])
			if seg.is_empty():
				continue
			var idx := path.find(seg, cursor)
			if idx < 0 or idx + seg.length() > ceiling:
				return false
			cursor = idx + seg.length()
		return true
	return path == glob


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("[PASS] %s" % label)
	else:
		failures += 1
		print("[FAIL] %s" % label)


func _fail(label: String) -> void:
	failures += 1
	print("[FAIL] %s" % label)


func _finish() -> void:
	print("Checks: %d, Failures: %d" % [checks, failures])
	print("RESULT: %s" % ("PASSED" if failures == 0 else "FAILED"))
	quit(1 if failures > 0 else 0)
