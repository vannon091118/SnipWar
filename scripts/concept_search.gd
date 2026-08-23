#!/usr/bin/env -S godot --headless --path . --script

## concept_search.gd — Schnelle Code-Suche via ConceptIndex (ohne Preflight-Suite)
##
## Nutzung:
##   $GODOT_BIN --headless --path . --script res://scripts/concept_search.gd "suchbegriff"
##   $GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --domain economy
##   $GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --class ShipManager
##   $GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --list-domains
##   $GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --list-concepts
##
## Vorteile ggü. grep/rg:
## - Sucht nach semantischen Konzepten (Domänen, Klassen, Methoden), nicht nur Text
## - Liefert Dateipfade, Klassen, Methoden, Beschreibung in einem Ergebnis
## - Deutsch/Englisch-Synonyme eingebaut
## - Keine falschen Treffer in Kommentaren/Strings

extends SceneTree

const _Index := preload("res://scripts/concept_index.gd")

var _args: Dictionary = {}
var _index: ConceptIndex

func _init() -> void:
	_parse_args()
	_index = _Index.new()

	if _args.has("help") or _args.has("h"):
		_print_help()
		quit(0)
		return

	if _args.has("list-domains"):
		_print_domains()
		quit(0)
		return

	if _args.has("list-concepts"):
		_print_concepts()
		quit(0)
		return

	if _args.has("domain"):
		_print_domain(_args["domain"])
		quit(0)
		return

	if _args.has("class"):
		_print_class(_args["class"])
		quit(0)
		return

	if _args.has("unmapped"):
		_print_unmapped()
		quit(0)
		return

	if _args.has("free-slots"):
		_print_free_slots()
		quit(0)
		return

	# Default: search query
	var query: String = _args.get("query", "")
	if query.is_empty():
		print("Fehler: Suchbegriff fehlt. Nutze --help für Hilfe.")
		quit(1)
		return

	_search(query)

func _parse_args() -> void:
	var all_args: PackedStringArray = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())

	var i := 0
	while i < all_args.size():
		var arg: String = all_args[i]
		if arg.begins_with("--"):
			var key: String = arg.trim_prefix("--")
			if i + 1 < all_args.size() and not all_args[i + 1].begins_with("--"):
				_args[key] = all_args[i + 1]
				i += 2
			else:
				_args[key] = true
				i += 1
		elif arg.begins_with("-") and not arg.begins_with("--"):
			var key: String = arg.trim_prefix("-")
			if i + 1 < all_args.size() and not all_args[i + 1].begins_with("-"):
				_args[key] = all_args[i + 1]
				i += 2
			else:
				_args[key] = true
				i += 1
		else:
			_args["query"] = arg
			i += 1

func _search(query: String) -> void:
	var results: Array = _index.search(query)

	if results.is_empty():
		print("Keine Treffer für: %s" % query)
		quit(0)
		return

	print("=== ConceptIndex Search: '%s' (%d Treffer) ===" % [query, results.size()])
	print("")

	for entry in results:
		_print_entry(entry, query)

func _print_entry(entry, query: String) -> void:
	print("┌ %s [%s]" % [entry.concept, entry.domain])
	print("│  Beschreibung: %s" % entry.description)
	if not entry.classes.is_empty():
		print("│  Klassen: %s" % ", ".join(entry.classes))
	if not entry.methods.is_empty():
		print("│  Methoden: %s" % ", ".join(entry.methods))
	if not entry.files.is_empty():
		print("│  Dateien:")
		for file in entry.files:
			print("│    %s" % file)
	print("└─")
	print("")

func _print_domain(domain: String) -> void:
	var entries: Array = _index.by_domain(domain)
	if entries.is_empty():
		print("Domäne nicht gefunden: %s" % domain)
		print("Verfügbare Domänen: %s" % ", ".join(_index.domains()))
		quit(1)
		return

	print("=== Domäne: %s (%d Konzepte) ===" % [domain, entries.size()])
	print("")
	for entry in entries:
		print("  • %s — %s" % [entry.concept, entry.description])
		if not entry.classes.is_empty():
			print("    Klassen: %s" % ", ".join(entry.classes))
		print("")

func _print_class(cls_name: String) -> void:
	var entry = _index.class_concept(cls_name)
	if entry == null:
		print("Klasse nicht im Index: %s" % cls_name)
		quit(1)
		return

	print("=== Klasse: %s ===" % cls_name)
	print("Konzept: %s [%s]" % [entry.concept, entry.domain])
	print("Beschreibung: %s" % entry.description)
	print("Dateien: %s" % (", ".join(entry.files) if not entry.files.is_empty() else "—"))
	print("Methoden: %s" % (", ".join(entry.methods) if not entry.methods.is_empty() else "—"))

func _print_unmapped() -> void:
	var unmapped: Array[String] = _index.get_unmapped_classes()
	if unmapped.is_empty():
		print("Keine ungemappten Klassen gefunden. Alle class_name-Dateien sind im Index.")
		return
	print("=== Ungemappte Klassen (%d) ===" % unmapped.size())
	print("")
	for cls in unmapped:
		var file_path: String = _index._class_to_file.get(cls, "?") as String
		print("  %s  (%s)" % [cls, file_path])
	print("")
	print("Tipp: Füge diese Klassen in _build_concepts() unter passendem Konzept ein.")

func _print_free_slots() -> void:
	var slots: Array[Dictionary] = _index.get_concepts_with_free_slots()
	if slots.is_empty():
		print("Alle Konzepte vollständig gemappt — keine freien Slots.")
		return
	print("=== Konzepte mit freien Slots ===")
	print("")
	for slot in slots:
		print("┌ %s [%s] — %d/%d gemappt (%d frei)" % [slot.concept, slot.domain, slot.mapped, slot.total, slot.missing])
		print("│  Beschreibung: %s" % slot.description)
		if not slot.classes.is_empty():
			print("│  Erwartete Klassen: %s" % ", ".join(slot.classes))
		if not slot.files.is_empty():
			print("│  Bereits gemappte Dateien: %s" % ", ".join(slot.files))
		print("└─")
		print("")

func _print_domains() -> void:
	print("=== Verfügbare Domänen ===")
	for domain in _index.domains():
		var count: int = _index.by_domain(domain).size()
		print("  %s (%d Konzepte)" % [domain, count])

func _print_concepts() -> void:
	print("=== Alle Konzepte ===")
	for entry in _index.get_all():
		print("  %s [%s] — %s" % [entry.concept, entry.domain, entry.description])

func _print_help() -> void:
	print("""
ConceptIndex Search — Schnelle semantische Code-Suche für SnipWar
==================================================================

NUTZUNG:
  $GODOT_BIN --headless --path . --script res://scripts/concept_search.gd [OPTIONEN] [SUCHBEGRIFF]

BEFEHLE:
  (kein Flag)           Suche nach Begriff (Konzepte, Klassen, Methoden, Dateien, Synonyme)
  --domain, -d <name>   Alle Konzepte einer Domäne anzeigen
  --class, -c <name>    Details zu einer spezifischen Klasse
  --list-domains        Alle Domänen auflisten
  --list-concepts       Alle Konzepte auflisten
  --unmapped            Alle class_name-Klassen zeigen, die noch in KEINEM Konzept gemappt sind
  --free-slots          Konzepte anzeigen, die noch nicht alle erwarteten Klassen haben
  --help, -h            Diese Hilfe

BEISPIELE:
  # Suche nach "fleet" (findet fleet_management Konzept + ShipManager, FleetSnapshot, etc.)
  $GODOT_BIN --headless --path . --script res://scripts/concept_search.gd fleet

  # Suche mit deutschem Synonym
  $GODOT_BIN --headless --path . --script res://scripts/concept_search.gd schiff

  # Alle Economy-Konzepte
  $GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --domain economy

  # Details zu ShipManager
  $GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --class ShipManager

  # Alle Domänen anzeigen
  $GODOT_BIN --headless --path . --script res://scripts/concept_search.gd --list-domains

DOMÄNEN: ships, economy, transit, navigation, world, planets, combat, tech, ui, scenes, preflight, ai, missions, background, events, input, factions, state

SYNONYME (DE/EN): fleet/flotte, ship/schiff, economy/ökonomie, resource/ressource,
                  worker/arbeiter, planet/planetoid, combat/kampf, technology/technologie,
                  research/forschung, menu/menü, save/speichern, load/laden, etc.
""")