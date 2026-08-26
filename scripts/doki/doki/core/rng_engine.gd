class_name DOKI_RngEngine
extends RefCounted
## Deterministische RNG-Engine, Port aus dem XBridge.DOKI-System (RngEngine.cs, 1:1).
## KEIN RandomNumberGenerator, KEINE Zeit — alles reine Funktion des Inputs.

## Feld-Definitionen: Key, Source ("sequence" | "rng"), Default-Pool (rng only).
## Reihenfolge definiert das Composite-Format.
const FIELD_C: String = "c"
const FIELD_J: String = "j"
const FIELD_N: String = "n"
const FIELD_A: String = "a"
const FIELD_P: String = "p"

const COMPOSITE_REGEX: String = "^c(\\d+)j(\\d+)n(\\d+)a(\\d+)p(\\d+)$"

## Genesis-Werte
const GENESIS_COMPOSITE: String = "c0j0n0a0p0"
const GENESIS_MOOD: String = "genesis"


## ─── djb2 (deterministischer 32-bit Hash) ───────────────────────────────
static func djb2(str: String) -> int:
	var hash: int = 5381
	for i in str.length():
		var c: int = str.unicode_at(i)
		hash = ((hash << 5) + hash + c) & 0xFFFFFFFF
	return hash


## ─── Composite: Kennen/Aufbauen ─────────────────────────────────────────
## Zerlegt "c5j86n9a1p1" → {c:5, j:86, n:9, a:1, p:1}
static func parse_composite(composite: String) -> Dictionary:
	var result: Dictionary = {FIELD_C: 0, FIELD_J: 0, FIELD_N: 0, FIELD_A: 0, FIELD_P: 0}
	var re := RegEx.new()
	re.compile(COMPOSITE_REGEX)
	var m: RegExMatch = re.search(composite)
	if m != null:
		result[FIELD_C] = int(m.get_string(1))
		result[FIELD_J] = int(m.get_string(2))
		result[FIELD_N] = int(m.get_string(3))
		result[FIELD_A] = int(m.get_string(4))
		result[FIELD_P] = int(m.get_string(5))
	return result


## Baut "c5j86n9a1p1" aus Feld-Dictionary.
static func build_composite(fields: Dictionary) -> String:
	return "c%dj%dn%da%dp%d" % [fields[FIELD_C], fields[FIELD_J], fields[FIELD_N], fields[FIELD_A], fields[FIELD_P]]


## ─── Mood deterministisch, garantiert != prev_mood ───────────────────────
static func select_mood(j: int, prev_mood: String, pool: Array) -> String:
	if pool.is_empty():
		return "neutral"
	var mood_index: int = posmod(j, pool.size())
	if pool[mood_index] == prev_mood:
		mood_index = posmod(mood_index + 1, pool.size())
	return pool[mood_index]


## ─── decodeJ: j → {tone, structure, callback} ───────────────────────────
static func decode_j(j: int, mood_pool: Array, decoding: Dictionary) -> Dictionary:
	if j == 0:
		return {"tone": GENESIS_MOOD, "structure": "genesis", "callback": false}

	var tones: Array = mood_pool
	var structures: Array = ["chronologisch", "problem_lösung", "flashback", "dialog", "faktenliste"]

	var tone_values: Dictionary = decoding.get("tone", {}).get("values", {})
	var struct_values: Dictionary = decoding.get("structure", {}).get("values", {})
	if not tone_values.is_empty():
		var keys: Array = tone_values.keys()
		keys.sort_custom(func(a, b): return int(a) < int(b))
		if not keys.is_empty():
			tones = []
			for k in keys:
				tones.append(tone_values[k].get("tone", ""))
	if not struct_values.is_empty():
		var skeys: Array = struct_values.keys()
		skeys.sort_custom(func(a, b): return int(a) < int(b))
		if not skeys.is_empty():
			structures = []
			for k in skeys:
				structures.append(struct_values[k].get("structure", ""))

	return {
		"tone": tones[posmod(j, tones.size())],
		"structure": structures[posmod(j, structures.size())],
		"callback": j > 50,
	}


## ─── Derive: nächster Composite aus vorherigem + Inhalt ─────────────────
## Kausaler Seed: Composite + Tree-State + Diff-Inhalt + Impuls.
## Gleicher Input → identischer Composite (Narrator, Mood, Tone).
static func derive(
	prev_composite: String,
	tree_hash: String,
	diff_hash: String,
	impulse: String,
	limits: Dictionary,
	prev_mood: String,
	mood_pool: Array
) -> Dictionary:
	assert(not tree_hash.is_empty(), "derive: treeHash ist Pflichtfeld.")
	assert(not diff_hash.is_empty(), "derive: diffHash ist Pflichtfeld.")

	var prev: Dictionary = parse_composite(prev_composite)
	var seed: int = djb2(prev_composite + tree_hash + diff_hash + impulse)
	var rng := DOKI_XorShift128.new(seed)

	var next: Dictionary = {}
	for field_key in [FIELD_C, FIELD_J, FIELD_N, FIELD_A, FIELD_P]:
		var prev_value: int = int(prev.get(field_key, 0))
		if field_key == FIELD_C:
			# Sequence: monoton hoch
			next[field_key] = prev_value + 1
		else:
			var max_val: int = int(limits.get(field_key, 100))
			if max_val > 0:
				next[field_key] = rng.next_int(1, max_val + 1)
			else:
				next[field_key] = 1

	# Mood — nie derselbe wie vorheriger
	var mood: String = select_mood(int(next[FIELD_J]), prev_mood, mood_pool)

	return {
		"composite": build_composite(next),
		"seed": seed,
		"tree_hash": tree_hash,
		"diff_hash": diff_hash,
		"mood": mood,
		"c": int(next[FIELD_C]),
		"j": int(next[FIELD_J]),
		"n": int(next[FIELD_N]),
		"a": int(next[FIELD_A]),
		"p": int(next[FIELD_P]),
	}


## posmod: GDScript % kann negativ liefern — für deterministische Indizes fixieren.
static func posmod(value: int, mod: int) -> int:
	var r: int = value % mod
	if r < 0:
		r += mod
	return r