class_name DOKI_RngEngine
extends RefCounted
## Deterministische RNG-Engine, Port aus dem XBridge.DOKI-System (RngEngine.cs, 1:1).
## KEIN RandomNumberGenerator, KEINE Zeit — alles reine Funktion des Inputs.
## Domain separation via HMAC (V8-002), integer arithmetic (V8-003), mood pool guard (V8-004).

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

## Domain separation key for HMAC (V8-002)
const DOMAIN_KEY: String = "DOKI_RNG_DERIVE_V2"


## ─── djb2 (deterministischer 32-bit Hash) ───────────────────────────────
static func djb2(str: String) -> int:
	var hash: int = 5381
	for i in str.length():
		var c: int = str.unicode_at(i)
		hash = ((hash << 5) + hash + c) & 0xFFFFFFFF
	return hash


## ─── HMAC-SHA256 for domain separation (V8-002) ──────────────────────────
static func _hmac_sha256(key: String, data: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	# Simple HMAC: SHA256(key + SHA256(key + data))
	var inner_ctx := HashingContext.new()
	inner_ctx.start(HashingContext.HASH_SHA256)
	inner_ctx.update(key.to_utf8_buffer())
	inner_ctx.update(data.to_utf8_buffer())
	var inner_hash: PackedByteArray = inner_ctx.finish()
	ctx.update(key.to_utf8_buffer())
	ctx.update(inner_hash)
	return ctx.finish().hex_encode()


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
## Guard pool_size >= 2 (V8-004)
static func select_mood(j: int, prev_mood: String, pool: Array) -> String:
	if pool.is_empty():
		return "neutral"
	if pool.size() < 2:
		# Can't guarantee != prev_mood with only 1 mood
		return pool[0]
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
## Domain separation via HMAC (V8-002), deterministic inputs only (V5-001).
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
	
	# Domain-separated seed via HMAC (V8-002)
	var seed_data: String = prev_composite + tree_hash + diff_hash + impulse
	var hmac_result: String = _hmac_sha256(DOMAIN_KEY, seed_data)
	# Use first 8 hex chars (32 bits) as seed
	var seed: int = int("0x" + hmac_result.substr(0, 8))
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