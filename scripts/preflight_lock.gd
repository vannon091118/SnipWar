extends RefCounted
## Cross-Process Preflight-Mutex (TASK: Preflight-Seriell-Takt).
##
## Problembild: Mehrere Agenten / Hooks starten gleichzeitig Godot-Preflight-Läufe
## (check.gd, preflight.gd, test_all.gd) — der Task-Manager zeigt dann mehrere
## konkurrierende Godot-Prozesse, die sich um dieselben Resourcen (Cache, Slots,
## Scene-Constraints) streiten. Verträge: NUR EIN Preflight-Lauf gleichzeitig.
## Ein zweiter Lauf blockt in einer Warteschlange, bis der laufende fertig ist.
##
## Mechanik: Lockfile-basierter Mutex unter user:// (überlebt Repo-Wechsel, wird
## nie committed). try_acquire() ist atomic genug (Stale-Erkennung nach
## STALE_SECONDS holt sich ein verwaistes Lock zurück — Crash-Selbstheilung).
## acquire_blocking() pollt im Sekundentakt und druckt Warteschlangen-Status.
##
## Nutzung in Entry-Points:
##   var lock := preload("res://scripts/preflight_lock.gd")
##   var res: Dictionary = lock.acquire_blocking("check.gd")
##   if not res.ok: quit(1); return
##   ... Arbeit ...
##   lock.release(res.token)

const LOCK_PATH := "user://preflight_gate.lock"
## Lock gilt als verwaist, wenn älter als dieser Wert (Sekunden). test_all-Volläufe
## können 10+ Minuten dauern; 20 Minuten sind eine sichere Obergrenze.
const STALE_SECONDS := 1200
const POLL_MS := 500
## Maximaler Blockier-Wunsch. Danach hart failen statt endlos hängen.
const MAX_WAIT_SECONDS := 3600


static func _read_lock() -> Dictionary:
	if not FileAccess.file_exists(LOCK_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOCK_PATH))
	if parsed is Dictionary:
		return parsed
	return {}


static func _write_lock(owner: String) -> void:
	var payload := JSON.stringify({
		"owner": owner,
		"pid": OS.get_process_id(),
		"created": Time.get_unix_time_from_system(),
	})
	var file := FileAccess.open(LOCK_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(payload)
	file.close()


static func _lock_age_seconds() -> float:
	if not FileAccess.file_exists(LOCK_PATH):
		return 0.0
	var mtime: float = FileAccess.get_modified_time(LOCK_PATH)
	return maxf(0.0, Time.get_unix_time_from_system() - mtime)


## Einmaliger, nicht-blockierender Acquire-Versuch.
## Rückgabe: {ok: bool, token: String (bei ok), holder: String, age: float, stale: bool}
static func try_acquire(owner: String) -> Dictionary:
	var lock: Dictionary = _read_lock()
	if FileAccess.file_exists(LOCK_PATH):
		var age: float = _lock_age_seconds()
		if age < float(STALE_SECONDS):
			return {
				"ok": false,
				"token": "",
				"holder": str(lock.get("owner", "?")),
				"age": age,
				"stale": false,
			}
		# Verwaistes Lock (Crash des Halters): übernehmen.
	var token := "%s:%d" % [owner, OS.get_process_id()]
	_write_lock(owner)
	return {"ok": true, "token": token, "holder": "", "age": 0.0, "stale": FileAccess.file_exists(LOCK_PATH)}


## Blockierender Acquire mit Warteschlange: pollt bis das Lock frei ist.
## Druckt alle 10 Sekunden einen Warteschlangen-Status (kein stiller Stillstand).
## Rückgabe: {ok: bool, token: String, error: String}
static func acquire_blocking(owner: String) -> Dictionary:
	var waited_ms := 0
	var last_status_ms := -10000
	while waited_ms < MAX_WAIT_SECONDS * 1000:
		var res: Dictionary = try_acquire(owner)
		if bool(res.get("ok", false)):
			if waited_ms > 0:
				print("[preflight-lock] Warteschlange aufgelöst nach %.1f s — Lock übernommen." % [float(waited_ms) / 1000.0])
			return {"ok": true, "token": str(res.get("token", "")), "error": ""}
		if waited_ms - last_status_ms >= 10000:
			last_status_ms = waited_ms
			print("[preflight-lock] Warteschlange: Preflight läuft (holder=%s, %.0f s) — blocke bis fertig." % [
				str(res.get("holder", "?")), float(res.get("age", 0.0))
			])
		OS.delay_msec(POLL_MS)
		waited_ms += POLL_MS
	return {"ok": false, "token": "", "error": "preflight-lock: Warteschlangen-Timeout nach %d s — holder=%s ist vermutlich hängengeblieben." % [MAX_WAIT_SECONDS, str(_read_lock().get("owner", "?"))]}


## Lock freigeben. Ignoriert still, wenn das Lock inzwischen jemand anderem gehört.
static func release(token: String) -> void:
	if token.is_empty():
		return
	if not FileAccess.file_exists(LOCK_PATH):
		return
	var lock: Dictionary = _read_lock()
	var current := "%s:%d" % [str(lock.get("owner", "")), int(lock.get("pid", -1))]
	if current == token:
		DirAccess.remove_absolute(LOCK_PATH)
