# MCP-Anomalien — GAME vs MCP Mismatch-Referenz
**Stand:** 2026-08-24 · **Session:** Playtest-Durchlauf SnipWar

Dieses Dokument trennt klar zwischen **GAME-Bugs** (Spiel-Logik/UI-Fehler) und **MCP-Mismatches** (Tool-API-Probleme, die MCP-Agent-Tests behindern).

---

## 🔴 GAME-MISMATCHES (Spiel-Fehler)

Das sind Fehler IM SPIEL, die durch MCP-Tests AUFGEDECKT wurden.

### G1 — PaperDossier CloseButton durch Sheet-Rotation unzuverlässig
```
Datei:    scripts/ui/dossier/paper_dossier.gd:141
Trigger:  _sheet.rotation = deg_to_rad(-1.1)
MCP:      runtime_ux_find("SCHLIESSEN") → match_score=0.75, Click daneben
Spieler:  ✕-Button manchmal unresponsive (~40% Fail-Rate)
Kategorie: UI / Transform-Bug
```

### G2 — Sub-Tab-Wechsel aktualisiert Content nicht
```
Datei:    scripts/objects/planets/planet_network_ui.gd
Trigger:  Klick auf ECONOMY/WERKSTATT während FORSCHUNG offen
MCP:      runtime_ux_click → clicked:true aber Panel-Inhalt unverändert
Spieler:  Tab-Leiste funktionslos
Kategorie: UI / State Management
```

### G3 — Forschung instant, kein Status-Tracking
```
Datei:    resources/config/technology_catalog_default.tres + tech_domain.gd
Trigger:  Alle research_time-Werte = 0.0
MCP:      game_research_status → {active:[], completed:[]} trotz gekaufter Techs
Spieler:  Kein Fortschritt, kein Timer, kein Indikator
Kategorie: Game Logic / Feedback
```

### G4 — 5 identische "BAUEN"-Buttons, per Path disabled
```
Datei:    PlanetPanel UpgradeList (planet_network_ui.gd)
Trigger:  5 Buttons mit Text "BAUEN", identische Labels
MCP:      runtime_ux_click(text) → kein eindeutiges Target
          runtime_click(path) → "Control is disabled"
Spieler:  Mausklick funktioniert, aber Accessibility/Tests unmöglich
Kategorie: UI / Accessibility
```

### G5 — Kamera-Startposition extrem weit entfernt
```
Datei:    map_camera.gd / world_bootstrap.gd
Trigger:  Kamera bei (-6663, -6873) nach World-Generation
MCP:      12+ runtime_drag-Aufrufe nötig um Planeten zu erreichen
Spieler:  Sieht leeren Weltraum, muss manuell pannen
Kategorie: Camera / Onboarding
```

### G6 — Economy zeigt "Keine laufende Produktion" bei Start
```
Datei:    economy_window.gd
Trigger:  Keine Basis-Einkommensquellen sichtbar
MCP:      game_resources_all → korrekt, aber game_vault_snapshot zeigt keine Produktion
Spieler:  Unklar wie Wirtschaft funktioniert
Kategorie: Economy / Onboarding
```

### G7 — Deaktivierte Techs ohne Tooltip
```
Datei:    parchment_tech_tree_view.gd
Trigger:  23/26 Techs disabled
MCP:      runtime_inspect_node zeigt kein tooltip_text
Spieler:  Weiß nicht WARUM Tech deaktiviert ist
Kategorie: UI / Feedback
```

---

## 🔴 MCP-MISMATCHES (Tool-API-Probleme)

Das sind Probleme der MCP-TOOLS selbst — sie blockieren den Test-Workflow.

### M1 — `runtime_ux_analyze({include_visual:true})` Response zu groß
```
Tool:     runtime_ux_analyze
Trigger:  include_visual:true bei 139 Controls → Response >100KB
Fehler:   Node.js JSON.parse bricht ab ("Unexpected end of JSON input")
Fix:      max_controls-Parameter oder streaming response
Workaround: runtime_ux_scan (nur live, ohne visual)
```

### M2 — `game_faction_query()` liefert leeres Array
```
Tool:     game_faction_query
Trigger:  Aufruf ohne planet_id → erwartet alle Planeten
Fehler:   {count:0, planets:[]} obwohl 74+ Planeten existieren
Ursache:  _faction_query() sucht get_faction() auf flachen PlanetField-Kindern,
          aber Planeten sind benamste Node2D-Container, die eigentlichen
          Planet-Objekte liegen eine Ebene tiefer
Fix:      Rekursive Suche oder planet_id-Pflicht
Workaround: runtime_get_scene_tree + manuelles Parsen
```

### M3 — `runtime_click` auf Nicht-Control-Nodes schlägt fehl
```
Tool:     runtime_click / runtime_ux_click
Trigger:  path=.../ClickArea (Area2D, keine Control)
Fehler:   "No click position available"
Ursache:  Welt-Planeten sind Node2D/Area2D → kein global_rect
Fix:      Weltkoordinate → Screen-Koordinate via Kamera-Mathe
Workaround: Kamera-Position + Sprite-Global-Position → Screen-Koordinate
            → runtime_click({x, y, inject_mode:"parse"})
```

### M4 — `runtime_eval` braucht Developer-Flag
```
Tool:     runtime_eval
Trigger:  Server ohne --mcp-developer gestartet
Fehler:   {"error":"eval requires developer mode (--mcp-developer)"}
Fix:      Server mit --mcp-developer starten
Workaround: runtime_inspect_node für Properties (nur lesend)
```

### M5 — Kein Auto-Reconnect nach Server-Neustart
```
Tool:     TCP-Transport
Trigger:  Godot-Prozess beendet und neu gestartet
Fehler:   ECONNREFUSED — Client muss neu verbinden
Fix:      Client-seitiger Reconnect-Loop
Workaround: Manuelles node-Reconnect
```

### M6 — Kein `runtime_camera_center_on` Tool
```
Tool:     NICHT VORHANDEN
Trigger:  Kamera soll zu Planet-Koordinaten springen
Fehler:   Nur runtime_drag verfügbar → umständlich
Fix:      Neues Tool: runtime_camera_move_to({x, y, zoom?, duration?})
Workaround: runtime_drag × N mit manueller Positionsprüfung
```

---

## 🟡 MCP-BEDIENUNGS-ANOMALIEN

Weniger kritisch, aber workflow-erschwerend.

### A1 — `runtime_ux_find` match_score ≠ Garantie
```
Tool:     runtime_ux_find
Beobachtung: Gefundener Button (score 0.75) ist klickbar, aber Click geht daneben
Ursache:   Sheet-Transform verschiebt visuelle vs. logische Position
Empfehlung: Nach jedem find → verify via rect-Position vs. center
```

### A2 — Viewport- vs Screen-Koordinaten-Verwirrung
```
Tool:     runtime_click, runtime_mouse_move
Beobachtung: Viewport = 960×540, Screen = 1280×720
            runtime_click-Scale: {x:1.33, y:1.33}
            Koordinaten müssen umgerechnet werden
Empfehlung: Immer viewport-Koordinaten verwenden (0–960, 0–540)
            runtime_click rechnet intern um
```

### A3 — `runtime_drag` Dauer unklar
```
Tool:     runtime_drag
Beobachtung: duration_ms=1000, aber Kamera-Delta variiert
            Kamera-Pan-Distanz hängt von Zoom ab
Empfehlung: Nach jedem Drag → runtime_inspect_node(MapCamera.position) prüfen
```

### A4 — Screenshot-Timing
```
Tool:     runtime_screenshot (async)
Beobachtung: Screenshot braucht 1-2 Frames → Frame-ID springt
            Response enthält context_id aber nicht direkt lesbar
Empfehlung: Screenshot nur für visuelle Inspektion, nicht für Echtzeit-Checks
```

### A5 — Kein Hover-Tooltip im Spiel → Hover-Events nicht validierbar
```
Tool:     runtime_mouse_move
Beobachtung: Maus-Hover feuert, aber kein Tooltip-System im Spiel
            → Hover-Effekte nicht via MCP testbar
Empfehlung: Spiel braucht Hover-Tooltips (→ Sprint 6, S2)
```

### A6 — JSON-Response-Parsing Fehleranfällig
```
Tool:     Alle tools/call
Beobachtung: Response ist nested JSON: content[{type:"text", text:"{...}"}]
            Doppeltes JSON.parse nötig
            Bei großen Responses bricht erstes parse nicht ab, aber Text wird abgeschnitten
Empfehlung: Response-Size-Limit dokumentieren; streaming oder pagination
```

---

## 📊 ZUSAMMENFASSUNG

| Kategorie | Count | Kritisch | Mittel |
|-----------|-------|----------|--------|
| GAME-Bugs | 7 | 5 | 2 |
| MCP-Tool-Bugs | 6 | 4 | 2 |
| MCP-Bedienung | 6 | 0 | 6 |

**Top-3-Fixes für nächste MCP-Session:**
1. `runtime_camera_move_to` Tool hinzufügen (erspart 12+ Drag-Calls)
2. `game_faction_query` rekursiv oder mit planet_id-Pflicht fixen
3. `--mcp-developer` als Default für Test-Sessions