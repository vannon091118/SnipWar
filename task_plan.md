# Separation of Concerns, Repository-Hygiene & Verkabelungsabsicherung

## Ziel
MCP- und Projektcode klar trennen, tote/historische Artefakte korrekt einordnen, alle relevanten Verkabelungen nachvollziehbar absichern und nur nachgewiesene Defekte ändern.

## Phasen

### Phase 1 — Inventar und Baseline
**Status:** complete
- Git-Status und letzter Commit geprüft.
- Bestehende Planung gelesen.
- MCP-Dateien, SnipWar-Referenzen und dynamische Verkabelungen inventarisiert.

### Phase 2 — Separation of Concerns
**Status:** complete
- Adapter-/State-Auflösung aus dem generischen MCP-Kern heraus als optionale Konfiguration/Fallback behandelt.
- Playthrough-Archiv, Chain Controller und E2E-Pfade auf dieselben optionalen Projektpfade ausgerichtet.
- Historische Client-/Report-Dateien nicht gelöscht, da ihre Nutzung nicht sicher ausgeschlossen werden kann.

### Phase 3 — Verkabelungsabsicherung
**Status:** complete
- `load`, `preload`, `call`, `has_method`, NodePath- und Registry-Routing geprüft.
- Ungültige relative konfigurierte NodePaths in den geänderten Pfaden abgefangen.
- Fehlende Adapter, State-Nodes und EventLogs bleiben kontrollierte optionale Fälle.

### Phase 4 — Repository-Hygiene
**Status:** complete
- Keine destruktive Löschung ohne Referenznachweis.
- SnipWar-spezifische Historie von wiederverwendbarem Add-on getrennt dokumentiert.
- Keine neuen temporären Artefakte ins Repository aufgenommen.

### Phase 5 — Verifikation und Dokumentation
**Status:** complete
- MCP-Buildcheck erfolgreich.
- Vollständiger Godot-Preflight erfolgreich.
- Findings und Sitzungsfortschritt persistent aktualisiert.

## Next Step
Keine weiteren Änderungen erforderlich; Commit-Status und Review-Ergebnis berichten.

## Errors Encountered
| Fehler | Versuch | Auflösung |
|---|---:|---|
| Keine | — | — |

## Entscheidungen
| Entscheidung | Begründung |
|---|---|
| Historische Reports/Playthroughs nicht löschen | Nutzung und Bedeutung sind nicht vollständig beweisbar; Löschung wäre destruktiv. |
| Keine globale Refaktorierung | Scope bleibt auf echte Korrektheits-/Verkabelungsdefekte begrenzt. |
| Konventionelle Node-Namen nur als Fallback | Beliebige Godot-Projekte können eigene Pfade über `application/mcp/*` setzen. |
