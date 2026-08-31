class_name ChangeImpactResolver
extends RefCounted
## Deterministic staged-change impact resolution — the "missing middle" of the
## session-scoped verification contract.
##
##   changed files  →  affected contract(s)  →  required constraint closure
##
## Uses the ConstraintScanner as the single canonical source of impact
## metadata (no parallel registry). Fail-closed: an unknown path, an unmapped
## contract, or an empty resulting scope blocks instead of silently green.

const SCANNER_SCRIPT := preload("res://scripts/preflight_v2/constraint_scanner.gd")
const SCHEMA_VERSION := 1


## Compute a stable SHA-256 digest over the staged byte representation used by
## the gate (the exact `git diff --cached` blob bytes). Two concurrent agents
## producing the same staged tree yield the same digest → dedup-eligible.
static func staged_byte_digest(diff_output: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(diff_output.to_utf8_buffer())
	return ctx.finish().hex_encode()


## Stable digest over the sorted staged-path list (path identity, independent
## of byte drift — used to detect path-set changes vs. byte changes).
static func path_digest(staged_paths: Array) -> String:
	var paths := _normalized_paths(staged_paths)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("\n".join(paths).to_utf8_buffer())
	return ctx.finish().hex_encode()


## Stable digest over the resolved constraint set (the verification scope).
static func constraint_digest(constraints: Array) -> String:
	var sorted: Array = constraints.duplicate()
	sorted.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("\n".join(sorted).to_utf8_buffer())
	return ctx.finish().hex_encode()


## resolve(staged_paths) → {ok, error?, paths, contracts, constraints, schema_version}
## staged_paths: repo-relative file paths (from `git diff --cached --name-only`).
static func resolve(staged_paths: Array) -> Dictionary:
	var paths := _normalized_paths(staged_paths)
	if paths.is_empty():
		return {"ok": false, "error": "empty_staged_scope"}

	var scanner = SCANNER_SCRIPT.new()
	var path_map: Array = scanner.path_contracts()
	var contracts: Array[String] = []
	var unresolved: Array[String] = []

	for path in paths:
		# DOKI/managed narrative artifacts are an explicit contract, not unknown.
		if SCANNER_SCRIPT.AUTO_MANAGED.has(String(path).get_file()):
			if not contracts.has("doki"):
				contracts.append("doki")
			continue
		var hit_any: bool = false
		for rule in path_map:
			if _matches(path, str(rule["glob"])):
				hit_any = true
				for cid in rule["contracts"]:
					if not contracts.has(String(cid)):
						contracts.append(String(cid))
		if not hit_any:
			unresolved.append(path)

	if not unresolved.is_empty():
		unresolved.sort()
		return {"ok": false, "error": "unknown_impact:%s" % ",".join(unresolved)}

	# Build the transitive constraint closure over the affected contracts.
	var constraints: Array[String] = []
	for cid in contracts:
		for constraint in scanner.contract_constraints(cid):
			if not constraints.has(constraint):
				constraints.append(constraint)
	constraints.sort()

	if constraints.is_empty():
		return {"ok": false, "error": "unresolved_impact"}

	contracts.sort()
	paths.sort()
	return {
		"ok": true,
		"schema_version": SCHEMA_VERSION,
		"paths": paths,
		"contracts": contracts,
		"constraints": constraints,
	}


## resolve_status(staged_status) — engines that pass `git diff --cached
## --name-status` reject rename/copy/delete/D branches explicitly instead of
## guessing a mapping for them. A/D/M are passed through to resolve().
static func resolve_status(staged_status: Array) -> Dictionary:
	var paths: Array = []
	for raw in staged_status:
		var line: String = String(raw).strip_edges()
		if line.is_empty():
			continue
		var parts := line.split("\t")
		var status: String = str(parts[0]) if parts.size() > 0 else ""
		if not (status == "A" or status == "M"):
			return {"ok": false, "error": "unmapped_status:%s" % status}
		var path := str(parts[parts.size() - 1]).strip_edges()
		# Rename/copy forms carry an origin path after the arrow.
		for seg in range(1, parts.size()):
			path = str(parts[seg]).strip_edges()
		if path.is_empty():
			continue
		paths.append(path)
	return resolve(paths)


static func _normalized_paths(paths: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_path in paths:
		var path := str(raw_path).replace("\\", "/").strip_edges()
		if not path.is_empty() and not result.has(path):
			result.append(path)
	result.sort()
	return result


## Glob matcher for the *canonical* prefix forms used in _PATH_CONTRACTS:
##   path == glob | path under glob/** | * wildcard suffix
static func _matches(path: String, glob: String) -> bool:
	if glob == "*":
		return true
	if glob.ends_with("/**"):
		return path.begins_with(glob.trim_suffix("/**")) or path == glob.trim_suffix("/**")
	if glob.ends_with("**"):
		return path.begins_with(glob.trim_suffix("**"))
	if "*" in glob:
		var fixed: PackedStringArray = glob.split("*")
		return path.begins_with(str(fixed[0])) and path.ends_with(str(fixed[fixed.size() - 1]))
	return path == glob