class_name PreflightConstraintEventLog
extends RefCounted

## EventLog recording/toasts, message-feed cap and player.log export.

func constraint_name() -> String:
	return "event_log"


func run(ctx: PreflightContext) -> bool:
	var network: Node = ctx.network
	var event_log: Node = ctx.get_root().get_node_or_null("EventLog")
	if not ctx.check(event_log != null, "EventLog autoload is missing"):
		return false
	if not ctx.check(event_log.has_signal("message_pushed"), "EventLog must expose a typed message_pushed signal"):
		return false
	if not ctx.check(network.get_message_feed() != null, "message feed was not created by the network"):
		return false
	var before: int = event_log.get_entries().size()
	event_log.push(&"test", "Testnachricht")
	if not ctx.check(event_log.get_entries().size() == before + 1, "EventLog.push did not record an entry"):
		return false
	var pushed_entry: Dictionary = event_log.get_entries().back()
	if not ctx.check(bool(pushed_entry.get("visible", false)), "EventLog.push entry is not marked for the message feed"):
		return false
	event_log.log_silent(&"economy", "Stille Ressourcenmeldung")
	if not ctx.check(event_log.get_entries().size() == before + 2, "EventLog.log did not record an entry"):
		return false
	var silent_entry: Dictionary = event_log.get_entries().back()
	# EventLog is an autoload and intentionally outlives each scene fixture.
	# Seed the three domain messages locally so this constraint does not depend
	# on scout/economy constraints having run before it.
	event_log.push(&"discovery", "Scanbericht Fixture: Energie, Größe L, 2 Bauplätze.")
	event_log.push(&"economy", "Sammeltrupp Fixture begonnen: 1 Worker erntet fortan Rohstoffe.")
	event_log.push(&"economy", "Fixture: Worker-Fertiger in der Werft aktiviert.")
	if not ctx.check(not bool(silent_entry.get("visible", true)), "silent EventLog entry should not create a toast"):
		return false
	var history: Array[Dictionary] = event_log.get_entries()
	var scan_report_seen: bool = false
	var collection_report_seen: bool = false
	var factory_report_seen: bool = false
	for history_entry in history:
		var history_text: String = String(history_entry.get("text", ""))
		scan_report_seen = scan_report_seen or history_text.begins_with("Scanbericht")
		collection_report_seen = collection_report_seen or history_text.contains("Sammeltrupp")
		factory_report_seen = factory_report_seen or history_text.contains("Worker-Fertiger")
	if not ctx.check(scan_report_seen and collection_report_seen and factory_report_seen, "scan, collection or worker-factory event was not pushed"):
		return false
	var feed: MessageFeed = network.get_message_feed()
	var toast_list: VBoxContainer = feed.get_node_or_null("FeedRoot/ToastList") as VBoxContainer
	var theme_config: UIThemeConfig = network.get("ui_theme_config") as UIThemeConfig
	if not ctx.check(toast_list != null and theme_config != null, "message feed toast list or theme config is missing"):
		return false
	for index in range(theme_config.message_max_visible_toasts + 2):
		event_log.push(&"test", "Toast %d" % index)
	if not ctx.check(toast_list.get_child_count() <= theme_config.message_max_visible_toasts, "message feed exceeded its configured toast limit"):
		return false
	if not ctx.check(event_log.export_to_player_log("user://preflight_player.log"), "EventLog export_to_player_log failed"):
		return false
	var file := FileAccess.open("user://preflight_player.log", FileAccess.READ)
	if not ctx.check(file != null, "player.log export file is missing"):
		return false
	var content := file.get_as_text()
	file.close()
	if not ctx.check(content.contains("Testnachricht") and content.contains("Stille Ressourcenmeldung"), "player.log export is missing recorded entries"):
		return false
	return true
