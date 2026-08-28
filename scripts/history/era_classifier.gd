class_name EraClassifier
extends RefCounted

## Klassifiziert historische Epochen dynamisch und emergent aus tatsächlichen Welt-Metriken.
## Ersetzt starre Jahreszeiten durch post-hoc Geschichtsschreibung (Dwarf-Fortress-Ansatz).

func classify_eras(events: Array[HistoryEvent], total_years: int = 300, segment_size: int = 75) -> Array[Dictionary]:
	if events.is_empty():
		return []

	var eras: Array[Dictionary] = []
	var start_year: int = -total_years

	# Teile die Chronik in Segmente
	var current_seg_start: int = start_year
	while current_seg_start < 0:
		var current_seg_end: int = mini(0, current_seg_start + segment_size)
		var seg_events: Array[HistoryEvent] = []
		for e in events:
			if e.year >= current_seg_start and e.year < current_seg_end:
				seg_events.append(e)

		var era: Dictionary = _evaluate_segment(seg_events, current_seg_start, current_seg_end)
		eras.append(era)
		current_seg_start = current_seg_end

	return eras


func _evaluate_segment(seg_events: Array[HistoryEvent], start_yr: int, end_yr: int) -> Dictionary:
	var total: int = seg_events.size()
	if total == 0:
		return {
			"name": "Die Vergessene Epoche",
			"start_year": start_yr,
			"end_year": end_yr,
			"dominant_theme": "stagnation",
			"description": "Eine Ära relativer Ruhe, in der kaum historische Dokumente überliefert sind."
		}

	var colonies: int = 0
	var conflicts: int = 0
	var diplomacy: int = 0
	var science: int = 0
	var casualties: int = 0

	for e in seg_events:
		casualties += e.casualties
		match e.event_type:
			&"colony", &"explore":
				colonies += 1
			&"conquest", &"defeat", &"attack", &"war_declared":
				conflicts += 1
			&"trade", &"alliance", &"rivalry":
				diplomacy += 1
			&"research":
				science += 1

	var conflict_ratio: float = float(conflicts) / float(total)
	var colony_ratio: float = float(colonies) / float(total)
	var science_ratio: float = float(science) / float(total)
	var diplo_ratio: float = float(diplomacy) / float(total)

	var era_name: String = ""
	var theme: String = ""
	var desc: String = ""

	if conflict_ratio > 0.35 or casualties > 100:
		theme = "conflict"
		era_name = "Das Zeitalter des Großen Zwists"
		desc = "Erbitterte Grenzkriege und Flottengefechte prägten diese Epoche. %d Opfer wurden in den Schlachten verzeichnet." % casualties
	elif colony_ratio > 0.15:
		theme = "expansion"
		era_name = "Die Ära der Ersten Pioniere"
		desc = "Die Fraktionen drangen in unerforschte Sektoren vor und gründeten die ersten dauerhaften Außenposten."
	elif science_ratio > 0.35 and diplo_ratio > 0.15:
		theme = "golden_age"
		era_name = "Das Goldene Zeitalter der Entdeckungen"
		desc = "Wirtschaftlicher Aufschwung, florierende Handelsrouten und wissenschaftliche Durchbrüche dominierten die Welten."
	elif diplo_ratio > 0.30:
		theme = "diplomacy"
		era_name = "Die Zeit der Bündnisse und Verträge"
		desc = "Intensive diplomatische Verhandlungen und Machtblöcke bestimmten das politische Gleichgewicht."
	else:
		theme = "reconstruction"
		era_name = "Die Epoche der Konsolidierung"
		desc = "Eine Phase des inneren Ausbaus, der wirtschaftlichen Erholung und vorsichtigen Stabilisierung."

	return {
		"name": era_name,
		"start_year": start_yr,
		"end_year": end_yr,
		"dominant_theme": theme,
		"description": desc,
		"event_count": total,
		"casualties": casualties
	}
