class_name ChronicleTemplateResolver
extends RefCounted

## Löst Template-Schlüssel über locale CSV-Dateien auf.
## Pattern analog zu DOKI's voice_composer.gd — aber einfacher.
## Ersetzt {placeholders} in Templates durch aktuelle Werte.
## NICHT via load() — via FileAccess.get_file_as_string() (Godot-Fallstrick!).

## Geladene Templates: { locale: { key: template } }
var _templates: Dictionary = {}

## Standard-Locale.
var _default_locale: String = "de"


func _init(locale_dir: String = "res://resources/locale", default_locale: String = "de") -> void:
	_default_locale = default_locale
	_load_locale(locale_dir.path_join("history_%s.csv" % default_locale))
	# Versuche weitere verfügbare Locales
	for locale in ["en", "fr", "es"]:
		var path: String = locale_dir.path_join("history_%s.csv" % locale)
		if FileAccess.file_exists(path):
			_load_locale(path)


## Lädt eine CSV-Locale-Datei.
func _load_locale(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("ChronicleTemplateResolver: %s not found" % path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("ChronicleTemplateResolver: cannot open %s" % path)
		return

	var locale: String = path.get_file().get_basename().replace("history_", "")
	var templates: Dictionary = {}

	# Header überspringen
	file.get_line()

	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.is_empty():
			continue

		# CSV-Parsing: key,template (einfach: erster Komma-Split)
		var comma_pos: int = line.find(",")
		if comma_pos < 0:
			continue

		var key: String = line.substr(0, comma_pos).strip_edges()
		var template: String = line.substr(comma_pos + 1).strip_edges()

		# Anführungszeichen entfernen
		if template.begins_with("\"") and template.ends_with("\""):
			template = template.substr(1, template.length() - 2)

		templates[key] = template

	file.close()
	_templates[locale] = templates
	print("ChronicleTemplateResolver: loaded %d templates for '%s'" % [templates.size(), locale])


## Löst einen Template-Key auf.
func resolve(template_key: String, context: Dictionary, locale: String = "") -> String:
	var effective_locale: String = locale if not locale.is_empty() else _default_locale
	var templates: Dictionary = _templates.get(effective_locale, {})

	var template: String = templates.get(template_key, "")
	if template.is_empty():
		# Fallback auf Default-Locale
		templates = _templates.get(_default_locale, {})
		template = templates.get(template_key, "")

	if template.is_empty():
		return "[%s]" % template_key  # Placeholder anzeigen

	# Placeholder-Ersetzung
	return _substitute(template, context)


## Ersetzt {placeholder} in einem Template.
func _substitute(template: String, context: Dictionary) -> String:
	var result: String = template
	for key in context:
		var placeholder: String = "{%s}" % String(key)
		var value: String = str(context[key])
		result = result.replace(placeholder, value)
	return result


## Gibt verfügbare Locales zurück.
func available_locales() -> Array[String]:
	var result: Array[String] = []
	for locale in _templates:
		result.append(locale)
	return result


## Prüft ob ein Template existiert.
func has_template(template_key: String, locale: String = "") -> bool:
	var effective_locale: String = locale if not locale.is_empty() else _default_locale
	var templates: Dictionary = _templates.get(effective_locale, {})
	return templates.has(template_key)


## Gibt alle Template-Keys für eine Locale zurück.
func template_keys(locale: String = "") -> Array[String]:
	var effective_locale: String = locale if not locale.is_empty() else _default_locale
	var templates: Dictionary = _templates.get(effective_locale, {})
	var result: Array[String] = []
	for key in templates:
		result.append(key)
	return result
