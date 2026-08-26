class_name DOKI_ChainStore
extends RefCounted
## Verwaltet narrative_chain.json (Repo-Root).
## Format (Port aus XBridge.CommitLayer):
## {
##   "genesis_composite": "c0j0n0a0p0",
##   "genesis_mood": "genesis",
##   "genesis_date": "2026-08-26 00:00:00",   ← einmalig beim init gesetzt (danach fix)
##   "anchor": { "hash": "...", "subject": "...", "date": "..." },  ← Git-HEAD beim init
##   "entries": [ { seq, hash, composite, mood, narrator, model_id, summary,
##                  prev_narrator, prev_model, date, data_changes } ]
## }

var _path: String


func _init(repo_root: String) -> void:
	_path = repo_root.path_join("narrative_chain.json")


func path() -> String:
	return _path


func exists() -> bool:
	return FileAccess.file_exists(_path)


func read() -> Dictionary:
	if not exists():
		return _empty()
	var text: String = FileAccess.get_file_as_string(_path)
	if text.is_empty():
		return _empty()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return _empty()


func _empty() -> Dictionary:
	return {
		"genesis_composite": DOKI_RngEngine.GENESIS_COMPOSITE,
		"genesis_mood": DOKI_RngEngine.GENESIS_MOOD,
		"genesis_date": "",
		"anchor": {},
		"entries": [],
	}


func save(chain: Dictionary) -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_error("DOKI: narrative_chain.json nicht schreibbar: %s" % _path)
		return
	file.store_string(JSON.stringify(chain, "\t"))
	file.close()


## Genesis einmalig setzen: Anker = aktueller HEAD, genesis_date = heute.
## Danach ist alles deterministisch (Timestamps = genesis_date + seq Stunden).
func init_genesis(head_hash: String, head_subject: String, head_date: String) -> Dictionary:
	var chain: Dictionary = read()
	if not chain.get("anchor", {}).is_empty():
		return chain
	chain["anchor"] = {
		"hash": head_hash,
		"subject": head_subject,
		"date": head_date,
	}
	if str(chain.get("genesis_date", "")).is_empty():
		chain["genesis_date"] = Time.get_date_string_from_system() + " 00:00:00"
	save(chain)
	return chain


func entries() -> Array:
	return read().get("entries", [])


func last_entry() -> Dictionary:
	var all: Array = entries()
	if all.is_empty():
		return {}
	return all[all.size() - 1]


## Deterministischer Timestamp: genesis_date + seq Stunden (kein DateTime.Now).
func entry_timestamp(seq: int) -> String:
	var chain: Dictionary = read()
	var genesis_date: String = str(chain.get("genesis_date", ""))
	if genesis_date.is_empty():
		genesis_date = "2026-01-01 00:00:00"
	# genesis_date ist "YYYY-MM-DD 00:00:00"
	var date_part: String = genesis_date.substr(0, 10)
	var hour: int = posmod(seq, 24)
	return "%s %02d:00:00" % [date_part, hour]


## Letzter Narrator, der NICHT der aktuelle ist (rückwärts suchen).
func previous_narrator(current_narrator: String) -> Dictionary:
	var all: Array = entries()
	for i in range(all.size() - 1, -1, -1):
		var narrator: String = str(all[i].get("narrator", ""))
		if not narrator.is_empty() and narrator != current_narrator:
			return {
				"name": narrator,
				"model_id": str(all[i].get("model_id", "")),
				"seq": int(all[i].get("seq", 0)),
				"composite": str(all[i].get("composite", "")),
				"summary": str(all[i].get("summary", "")),
			}
	return {}


func find_entry_by_hash(hash: String) -> Dictionary:
	for entry in entries():
		if str(entry.get("hash", "")).begins_with(hash) or str(entry.get("hash", "")) == hash:
			return entry
	return {}


## Neuen Eintrag nach erfolgreichem Commit anhängen.
func append_entry(
	commit_hash: String,
	composite: String,
	mood: String,
	narrator: String,
	model_id: String,
	summary: String,
	prev_narrator: String,
	prev_model: String,
	data_changes: Array,
	arc_id: String,
	p_id: int,
	counter: int,
	j: int,
	n: int,
	a: int,
	p: int
) -> Dictionary:
	var chain: Dictionary = read()
	var all: Array = chain.get("entries", [])
	var seq: int = all.size() + 1
	var entry := {
		"seq": seq,
		"hash": commit_hash,
		"composite": composite,
		"mood": mood,
		"narrator": narrator,
		"model_id": model_id,
		"date": entry_timestamp(seq),
		"summary": _truncate(summary, 200),
		"arc": arc_id,
		"p_id": seq,  # Plot-ID ist SEQUENZ (p1, p2, p3…) — wie im Original. Das
		              # RNG-gezogene Composite-p bleibt als Referenz-Feld unten.
		"c": counter,
		"j": j,
		"n": n,
		"a": a,
		"p": p,
		"data_changes": data_changes,
	}
	if not prev_narrator.is_empty():
		entry["prev_narrator"] = prev_narrator
		entry["prev_model"] = prev_model
	all.append(entry)
	chain["entries"] = all
	save(chain)
	return entry


## History-Seeding: fertig gebaute Einträge (init --seed-last N) anhängen.
## SEQ wird hier vergeben (nicht vom Caller) — garantiert lückenlos.
func seed_history(entries: Array) -> Dictionary:
	var chain: Dictionary = read()
	var all: Array = chain.get("entries", [])
	for e in entries:
		e["seq"] = all.size() + 1
		all.append(e)
	chain["entries"] = all
	save(chain)
	return {"ok": true, "count": entries.size()}


static func _truncate(s: String, max_len: int) -> String:
	if s.length() <= max_len:
		return s
	var cut: String = s.substr(0, max_len)
	var space_idx: int = cut.rfind(" ")
	if space_idx > 0:
		return cut.substr(0, space_idx) + "..."
	return cut + "..."


static func posmod(value: int, mod: int) -> int:
	var r: int = value % mod
	if r < 0:
		r += mod
	return r