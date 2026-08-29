##!/usr/bin/env gdscript
extends SceneTree
## Aktualisiert docs/METRICS_TRACKER.md nach jedem DOKI-Commit.
## Aufruf: $GODOT_BIN --headless --path . --script res://scripts/doki/metrics_updater.gd
##
## Liest narrative_chain.json + change_index.json + arcs.json,
## berechnet Metriken und schreibt docs/METRICS_TRACKER.md.

const CHAIN_PATH := "res://narrative_chain.json"
const CHANGE_INDEX_PATH := "res://change_index.json"
const ARCS_PATH := "res://scripts/doki/data/arcs.json"
const TRACKER_PATH := "res://docs/METRICS_TRACKER.md"

const FRUSTRATION_WEIGHT: float = 1.2
const RESPECT_WEIGHT: float = 0.5
const DECAY_FACTOR: float = 0.1


func _init() -> void:
	var chain := _read_json(CHAIN_PATH)
	var change_index := _read_json(CHANGE_INDEX_PATH)
	var arcs := _read_json(ARCS_PATH)

	if chain.is_empty():
		_err("Chain nicht lesbar: " + CHAIN_PATH)
		return

	var entries: Array = chain.get("entries", [])
	var anchor: Dictionary = chain.get("anchor", {})

	# Metriken berechnen
	var metrics := _calculate_metrics(entries, arcs)

	# Markdown generieren
	var md := _generate_markdown(metrics, entries, anchor, arcs)

	# Schreiben
	var full_path := ProjectSettings.globalize_path(TRACKER_PATH)
	var file := FileAccess.open(full_path, FileAccess.WRITE)
	if file == null:
		_err("Kann Tracker nicht schreiben: " + full_path)
		return
	file.store_string(md)
	file.close()

	print("METRICS_TRACKER aktualisiert: " + full_path)
	print("  Entries: %d | Active Arc: %s | Narratoren: %d" % [
		entries.size(),
		str(metrics.get("active_arc", "?")),
		metrics.get("narrator_count", 0)
	])
	quit(0)


func _calculate_metrics(entries: Array, arcs: Dictionary) -> Dictionary:
	var m := {}

	m["total_commits"] = entries.size()

	# Narrator-Verteilung
	var narrator_counts := {}
	var mood_counts := {}
	var arc_counts := {}
	var pair_counts := {}
	var narrator_bugs := {}
	var narrator_clean := {}
	var narrator_fixes := {}

	# Sentiment-Verlauf
	var running_sentiment: float = 5.0
	var sentiment_points := []

	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var n: String = str(e.get("narrator", "?"))
		var mood: String = str(e.get("mood", "?"))
		var arc: String = str(e.get("arc", "?"))
		var prev: String = str(e.get("prev_narrator", ""))
		var summary: String = str(e.get("summary", "")).to_lower()

		# Counts
		narrator_counts[n] = narrator_counts.get(n, 0) + 1
		mood_counts[mood] = mood_counts.get(mood, 0) + 1
		arc_counts[arc] = arc_counts.get(arc, 0) + 1

		# Pairs
		if not prev.is_empty():
			var pair: String = prev + " > " + n
			pair_counts[pair] = pair_counts.get(pair, 0) + 1

		# Bug/Fix Classification
		var is_fix := _has_term(summary, ["fix", "repair", "korr", "harden"])
		var is_bug := _has_term(summary, ["bug", "fehler", "break", "crash", "wip"])

		if is_fix:
			narrator_fixes[n] = narrator_fixes.get(n, 0) + 1
			running_sentiment = maxf(0.0, running_sentiment - FRUSTRATION_WEIGHT * 2.0)
		elif is_bug:
			narrator_bugs[n] = narrator_bugs.get(n, 0) + 1
			running_sentiment = maxf(0.0, running_sentiment - FRUSTRATION_WEIGHT)
		else:
			narrator_clean[n] = narrator_clean.get(n, 0) + 1
			running_sentiment = minf(10.0, running_sentiment + RESPECT_WEIGHT)

		sentiment_points.append(running_sentiment)

	# Narrator-Scores
	var narrator_scores := {}
	for n in narrator_counts:
		var bugs: int = narrator_bugs.get(n, 0)
		var clean: int = narrator_clean.get(n, 0)
		var fixes: int = narrator_fixes.get(n, 0)
		narrator_scores[n] = clean * RESPECT_WEIGHT - bugs * FRUSTRATION_WEIGHT - fixes * FRUSTRATION_WEIGHT * 2.0

	# Active Arc
	var active_arc := "?"
	var arc_data: Dictionary = arcs.get("arcs", {})
	for arc_id in arc_data:
		if str(arc_data[arc_id].get("status", "")) == "active":
			active_arc = arc_id
			break

	m["narrator_counts"] = narrator_counts
	m["mood_counts"] = mood_counts
	m["arc_counts"] = arc_counts
	m["pair_counts"] = pair_counts
	m["narrator_scores"] = narrator_scores
	m["narrator_bugs"] = narrator_bugs
	m["narrator_clean"] = narrator_clean
	m["narrator_fixes"] = narrator_fixes
	m["sentiment_points"] = sentiment_points
	m["active_arc"] = active_arc
	m["narrator_count"] = narrator_counts.size()
	m["final_sentiment"] = running_sentiment

	return m


func _generate_markdown(m: Dictionary, entries: Array, anchor: Dictionary, arcs: Dictionary) -> String:
	var now := Time.get_datetime_string_from_system()
	var last: Dictionary = entries[entries.size() - 1] if not entries.is_empty() else {}
	var last_seq: int = int(last.get("seq", 0))

	var md := "# 🔢 NARRATIVE METRICS TRACKER\n"
	md += "> Automatisch aktualisiert nach jedem DOKI-Commit.\n"
	md += "> Letzte Aktualisierung: `%s` | Chain-Eintrag: `c%d` | Arc: `%s`\n\n" % [now, last_seq, str(m.get("active_arc", "?"))]

	# Chain-Übersicht
	md += "---\n\n## 📊 CHAIN-ÜBERSICHT\n\n"
	md += "| Metrik | Wert |\n|--------|------|\n"
	md += "| **Gesamt-Commits (Chain)** | %d |\n" % m.get("total_commits", 0)
	md += "| **Aktiver Arc** | `%s` |\n" % str(m.get("active_arc", "?"))
	md += "| **Narratoren aktiv** | %d |\n" % m.get("narrator_count", 0)
	md += "| **Letzter Sentiment** | %.1f/10 |\n" % m.get("final_sentiment", 5.0)
	md += "\n"

	# Narrator-Trackrecord (sortiert nach Score)
	md += "---\n\n## 👥 NARRATOR-TRACKRECORD\n\n"
	md += "| Narrator | Commits | Bugs | Clean | Fixes | Score |\n"
	md += "|----------|---------|------|-------|-------|-------|\n"

	var sorted_narrators: Array = m.get("narrator_scores", {}).keys()
	sorted_narrators.sort_custom(func(a, b): return m["narrator_scores"][a] > m["narrator_scores"][b])

	for n in sorted_narrators:
		var score: float = m["narrator_scores"][n]
		var total: int = m["narrator_counts"].get(n, 0)
		var bugs: int = m["narrator_bugs"].get(n, 0)
		var clean: int = m["narrator_clean"].get(n, 0)
		var fixes: int = m["narrator_fixes"].get(n, 0)
		var icon := "🟢" if score > 1.0 else ("🟡" if score > -1.0 else "🔴")
		md += "| %s %s | %d | %d | %d | %d | **%+.1f** |\n" % [icon, n, total, bugs, clean, fixes, score]

	md += "\n"

	# Mood-Verteilung
	md += "---\n\n## 🎲 MOOD-VERTEILUNG\n\n"
	md += "| Mood | Anzahl | % |\n|------|--------|---|\n"
	var mood_sorted: Array = m.get("mood_counts", {}).keys()
	mood_sorted.sort_custom(func(a, b): return m["mood_counts"][a] > m["mood_counts"][b])
	var total_commits: int = m.get("total_commits", 1)
	for mood in mood_sorted:
		var count: int = m["mood_counts"][mood]
		var pct: float = float(count) / float(total_commits) * 100.0
		md += "| %s | %d | %.0f%% |\n" % [mood, count, pct]

	md += "\n"

	# Top Paare
	md += "---\n\n## 🔗 TOP NARRATOR-PAARUNGEN\n\n"
	md += "| Paar | Häufigkeit |\n|------|-----------|\n"
	var pair_sorted: Array = m.get("pair_counts", {}).keys()
	pair_sorted.sort_custom(func(a, b): return m["pair_counts"][a] > m["pair_counts"][b])
	for i in range(min(10, pair_sorted.size())):
		var pair: String = pair_sorted[i]
		var count: int = m["pair_counts"][pair]
		md += "| %s | %d |\n" % [pair, count]

	md += "\n"

	# Sentiment-Verlauf (ASCII-Art)
	md += "---\n\n## 📈 SENTIMENT-VERLAUF\n\n```\n"
	var points: Array = m.get("sentiment_points", [])
	if not points.is_empty():
		var bar_width: int = 50
		var step: float = float(points.size()) / float(bar_width)
		for x in range(bar_width):
			var idx: int = int(float(x) * step)
			idx = mini(idx, points.size() - 1)
			var val: float = points[idx]
			var bar_len: int = int(val)
			var line := "%3d │" % (x + 1)
			for _y in range(bar_len):
				line += "█"
			md += line + "\n"
	md += "```\n\n"

	# Empfehlungen
	md += "---\n\n## 🔧 KALIBRIERUNG\n\n"
	md += "| Parameter | Aktuell | Empfohlen |\n"
	md += "|-----------|---------|-----------|\n"
	md += "| `FRUSTRATION_WEIGHT` | %.1f | **2.0** |\n" % FRUSTRATION_WEIGHT
	md += "| `DECAY_FACTOR` | %.1f | **0.02** |\n" % DECAY_FACTOR
	md += "| `RESPECT_WEIGHT` | %.1f | **0.3** |\n" % RESPECT_WEIGHT

	md += "\n---\n\n*Dieses Dokument wird nach jedem DOKI-Finalize-Flow automatisch aktualisiert.*\n"

	return md


func _has_term(text: String, terms: Array) -> bool:
	for t in terms:
		if text.contains(t):
			return true
	return false


func _read_json(path: String) -> Dictionary:
	var full_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(full_path):
		return {}
	var file := FileAccess.open(full_path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return {}
	var result = json.data
	if result is Dictionary:
		return result
	return {}


func _err(msg: String) -> void:
	push_error("METRICS_UPDATER: " + msg)
	quit(1)
