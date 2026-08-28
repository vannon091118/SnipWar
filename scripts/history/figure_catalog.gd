class_name FigureCatalog
extends RefCounted

## Lädt historical_figures.json und bietet Zugriff auf Figuren-Muster.
## Pattern analog zu DOKI's narrator_catalog.gd.
## Enält Name-Pools, Rollen und Stimmen-Merkmale für historische Akteure.

var _figures: Array = []
var _name_pools: Dictionary = {}


func _init(data_dir: String) -> void:
	_load_figures(data_dir.path_join("historical_figures.json"))
	_load_name_pools(data_dir.path_join("name_pools.json"))


func _load_figures(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("FigureCatalog: %s not found" % path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		_figures = parsed.get("figures", [])


func _load_name_pools(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("FigureCatalog: %s not found" % path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		_name_pools = parsed


func all() -> Array:
	return _figures


func by_index(index: int) -> Dictionary:
	for f in _figures:
		if int(f.get("index", 0)) == index:
			return f
	return {}


func by_name(figure_name: String) -> Dictionary:
	for f in _figures:
		if str(f.get("name", "")) == figure_name:
			return f
	return {}


func name_by_index(index: int) -> String:
	return str(by_index(index).get("name", ""))


func get_name_pool(pool_name: String) -> Array:
	var pool: Array = _name_pools.get(pool_name, [])
	return pool


func pick_random_name(pool_name: String, rng: RandomNumberGenerator) -> String:
	var pool: Array = get_name_pool(pool_name)
	if pool.is_empty():
		return "Unknown"
	return str(pool[rng.randi_range(0, pool.size() - 1)])


func pick_random_title(rng: RandomNumberGenerator) -> String:
	var pool: Array = get_name_pool("titles")
	if pool.is_empty():
		return "Citizen"
	return str(pool[rng.randi_range(0, pool.size() - 1)])


func figure_count() -> int:
	return _figures.size()


func validate() -> bool:
	return not _figures.is_empty()
