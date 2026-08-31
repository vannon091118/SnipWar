class_name EconomyShopUnit
extends RefCounted

## QS-3: Shop-Ausgaben-Tracking. Verhaltens-Einheit für die EconomyDomain.
##
## Verantwortlich: record_purchase (Kauf-Event), faction_investments
## (Abfrage der kumulierten Ausgaben pro Fraktion), validate_investments.
##
## Die Unit trackt, wie viel jede Fraktion in Schiffe/Teile/Upgrades/Gebäude
## investiert hat — Credits UND Ressourcen. Das Sortiment kann basierend
## auf der Investitionshöhe wachsen (angebotsdynamisch), was ein zukünftiges
## Shop-Dossier speisen wird.
##
## State-Dictionarys und Signale bleiben auf der EconomyDomain-Fassade.

var _owner: EconomyDomain


func _init(owner: EconomyDomain) -> void:
	_owner = owner


## Zeichnet einen Kauf/Spend auf. category = "ship_part"|"upgrade"|"building"
## |"tech"|"worker_factory". resource_id/amount = Ressourcen-Kosten;
## credit_amount = Credits. Erhöht die kumulierten Zähler.
func record_purchase(faction: StringName, category: String, resource_id: StringName, resource_amount: int, credit_amount: int) -> void:
	if faction == &"" or category == &"":
		return
	var key: String = "%s::%s" % [String(faction), category]
	# Credits tracken
	var credits_spent: int = int(_owner.shop_credits_spent.get(key, 0))
	_owner.shop_credits_spent[key] = credits_spent + credit_amount
	# Ressourcen tracken (pro resource_id)
	var res_key: String = "%s::%s::%s" % [String(faction), category, String(resource_id)]
	var res_spent: int = int(_owner.shop_resources_spent.get(res_key, 0))
	_owner.shop_resources_spent[res_key] = res_spent + resource_amount
	# Gesamt-Zähler
	var total_key: String = String(faction)
	_owner.shop_total_investments[total_key] = int(_owner.shop_total_investments.get(total_key, 0)) + credit_amount + resource_amount


## Gibt die kumulierten Credits-Ausgaben pro Fraktion zurück (gesamt oder pro Kategorie).
func faction_investments(faction: StringName, category: String = "") -> Dictionary:
	var result: Dictionary = {"credits": 0, "resources": {}}
	var prefix: String = "%s::" % String(faction)
	for key in _owner.shop_credits_spent:
		if not String(key).begins_with(prefix):
			continue
		if category != &"" and not String(key).ends_with("::%s" % String(category)):
			continue
		result["credits"] = int(result["credits"]) + int(_owner.shop_credits_spent[key])
	# Ressourcen
	var res_prefix: String = "%s::" % String(faction)
	if category != &"":
		res_prefix = "%s::%s::" % [String(faction), String(category)]
	for rkey in _owner.shop_resources_spent:
		if not String(rkey).begins_with(res_prefix):
			continue
		var parts: PackedStringArray = String(rkey).split("::")
		var rid: String = parts[parts.size() - 1] if parts.size() >= 3 else ""
		if not rid.is_empty():
			result["resources"][rid] = int(result["resources"].get(rid, 0)) + int(_owner.shop_resources_spent[rkey])
	return result


## Liefert die Gesamtinvestition einer Fraktion (Credits + Ressourcen-Menge).
func total_investment(faction: StringName) -> int:
	return int(_owner.shop_total_investments.get(String(faction), 0))


## Bestimmt das Angebots-Tier basierend auf der Investitionshöhe.
## Tier 0 (Basis), 1 (fortgeschritten), 2 (Premium). Schwellen konfigurierbar.
func offer_tier(faction: StringName) -> int:
	var total: int = total_investment(faction)
	if total >= 500:
		return 2
	if total >= 150:
		return 1
	return 0


## Validierung: mindestens eine Fraktion muss Ausgaben haben.
func validate_investments() -> PackedStringArray:
	var errors := PackedStringArray()
	if _owner.shop_credits_spent.is_empty() and _owner.shop_resources_spent.is_empty():
		errors.append("no shop investments recorded")
	return errors


## Snapshot für Save/Load.
func capture_snapshot(data: RunSaveData) -> void:
	if data == null:
		return
	data.shop_credits_spent = _owner.shop_credits_spent.duplicate(true)
	data.shop_resources_spent = _owner.shop_resources_spent.duplicate(true)
	data.shop_total_investments = _owner.shop_total_investments.duplicate(true)


## Restore für Save/Load.
func restore_snapshot(data: RunSaveData) -> void:
	if data == null:
		return
	_owner.shop_credits_spent = RunSaveData.restore_dict(data.shop_credits_spent)
	_owner.shop_resources_spent = RunSaveData.restore_dict(data.shop_resources_spent)
	_owner.shop_total_investments = RunSaveData.restore_dict(data.shop_total_investments)
