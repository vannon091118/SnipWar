# Progress — Separation of Concerns & Repository-Hygiene

## Session 1 — 2026-08-26

### Abgeschlossen
- Aktuellen Git-Zustand und letzten Commit geprüft.
- Bestehende Planungsdateien gelesen und auf die neue Aufgabe ausgerichtet.
- MCP-Add-on-Dateien, historische SnipWar-Artefakte und dynamische Verkabelung inventarisiert.
- Adapter-/State-Auflösung aus Playthrough-Archiv, Chain Controller und E2E-Pfaden geprüft und abgesichert.
- Relative/ungültige konfigurierte NodePaths werden in den geänderten Suchpfaden nicht mehr an `get_node_or_null` übergeben.
- MCP Build Check erfolgreich ausgeführt.
- Vollständigen Godot-Preflight erfolgreich ausgeführt.
- Adversarial Review: `McpPlaythroughTools._state_fingerprint()` verwendete einen fehlenden Adapter-Resolver; projektagnostischen Resolver ergänzt.

### Ergebnis
- Build Check: PASS
- Preflight: 39/39 Constraints, 2020/2020 Assertions, RESULT: PASSED

### Noch offen
- Keine bestätigten Defekte im aktuellen Scope.
- Historische Reports/Client-Skripte und bekannte Headless-Test-/Leak-Warnungen bleiben Out of Scope.

### Fehler
- Keine neuen Fehler.

### Next Step
Änderungen prüfen und bei Bedarf als separaten Commit einreichen; kein automatischer Commit erfolgt.
