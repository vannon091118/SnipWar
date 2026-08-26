class_name DOKI_RelationshipEngine
extends RefCounted
## Dynamisches Sentiment (0-10) zwischen Narratoren, Port aus RelationshipEngine.cs (v2).
## Deterministisch: nutzt ausschließlich Chain-Timestamps, kein DateTime.Now.

const FRUSTRATION_WEIGHT: float = 1.2
const RESPECT_WEIGHT: float = 0.5
const DECAY_FACTOR: float = 0.1


## Baut NarratorContext für den Prompt: Wissen + Sentiment + ToneDirective.
func build_context(current_narrator: String, target_narrator: String, entries: Array) -> Dictionary:
	if entries.is_empty() or current_narrator == target_narrator:
		return {}

	var target_commits: Array = []
	for e in entries:
		if str(e.get("narrator", "")) == target_narrator:
			target_commits.append(e)
	if target_commits.is_empty():
		return {}

	var bug_commits: int = 0
	for tc in target_commits:
		if _has_term(str(tc.get("summary", "")), ["fix", "bug", "repair", "fehler", "korr"]):
			bug_commits += 1
	var clean_commits: int = target_commits.size() - bug_commits
	var fix_count: int = _count_fixes_after(entries, current_narrator, target_narrator)

	# Letzter Bug-Zeitpunkt als deterministischer Sequenz-Abstand zum Chain-Ende
	# (kein DateTime.Now, kein Time — reine Funktion der Chain).
	var bug_index: int = -1
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		if str(e.get("narrator", "")) == target_narrator and _has_term(str(e.get("summary", "")), ["fix", "bug"]):
			bug_index = i
			break
	var days_since: float = 90.0
	if bug_index >= 0:
		days_since = float(entries.size() - 1 - bug_index)
		if days_since > 90.0:
			days_since = 90.0

	var sentiment: float = clampf(
		5.0 - bug_commits * FRUSTRATION_WEIGHT + clean_commits * RESPECT_WEIGHT
		- fix_count * FRUSTRATION_WEIGHT * 2.0 + days_since * DECAY_FACTOR,
		0.0, 10.0
	)

	return {
		"target_narrator": target_narrator,
		"knowledge": _build_knowledge(target_narrator, target_commits.size(), bug_commits, clean_commits, fix_count, days_since),
		"sentiment": sentiment,
		"label": _sentiment_label(sentiment),
		"tone_directive": _build_tone_directive(sentiment, target_narrator, fix_count, bug_commits),
	}


static func _count_fixes_after(entries: Array, fixer: String, causer: String) -> int:
	var count: int = 0
	for i in range(1, entries.size()):
		if str(entries[i].get("narrator", "")) == fixer and str(entries[i - 1].get("narrator", "")) == causer:
			if _has_term(str(entries[i].get("summary", "")), ["fix", "repair"]):
				count += 1
	return count


static func _has_term(text: String, terms: Array) -> bool:
	for t in terms:
		if text.to_lower().contains(t):
			return true
	return false


static func _build_knowledge(target: String, total: int, bugs: int, clean: int, fixes: int, days_since: float) -> String:
	var parts: Array = []
	parts.append("%s hat %d Commits gemacht" % [target, total])
	if bugs > 0:
		parts.append("davon %d mit Bugs/Patches" % bugs)
	if clean > 0:
		parts.append("%d saubere Commits" % clean)
	if fixes > 0:
		parts.append("du musstest %d Mal hinter %s aufräumen" % [fixes, target])
	if days_since < 7.0 and bugs > 0:
		parts.append("der letzte Bug war vor %d Tagen" % int(days_since))
	if days_since >= 30.0:
		parts.append("der letzte Bug ist lange her — verjährt")
	return str(" ".join(parts)) + "."


static func _sentiment_label(s: float) -> String:
	if s >= 9.0: return "beste Zusammenarbeit"
	if s >= 7.5: return "respektiert die Arbeit"
	if s >= 6.0: return "professionell-neutral"
	if s >= 4.0: return "leicht genervt"
	if s >= 2.0: return "deutlich frustriert"
	return "will am liebsten kündigen"


static func _build_tone_directive(sentiment: float, target: String, fixes: int, bugs: int) -> String:
	if sentiment >= 8.0:
		return "Du schätzt %ss Arbeit. Lob ist angebracht." % target
	if sentiment >= 6.0:
		return ""
	if sentiment >= 4.0:
		if fixes > 0:
			return "Du bist leicht genervt von %ss Patzern. Zeig es subtil — ein sarkastischer Unterton, kein offener Angriff." % target
		return "Du findest %ss Arbeit okay, aber nicht brilliant. Leichte Skepsis." % target
	if sentiment >= 2.0:
		if fixes > 0:
			return "Du bist frustriert. %s hat dich %d Mal zum Aufräumen gezwungen. Sarkasmus ist erlaubt, Fluchen nicht." % [target, fixes]
		return "Du bist skeptisch gegenüber %ss Arbeit." % target
	if fixes > 0:
		return "DU BIST WÜTEND. %s hat %d Bugs produziert und du musstest %d Mal aufräumen. Dein Frust MUSS im Text spürbar sein — aber professionell." % [target, bugs, fixes]
	return "Du hast kein Vertrauen in %ss Arbeit." % target