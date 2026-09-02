# MCP Playtest Report — SnipWar v0.x
**Session:** 2026-08-24 · **Dauer:** ~45 min · **MCP-Server:** 116 Tools, Port 9090  
**Spieler:** KI-Agent via `runtime_ux_*` + `game_*` + `runtime_*` Tools  
**Godot:** 4.7.2 (Console) · **Start:** `-- --mcp --mcp-port 9090`

---

## ⚡ EXECUTIVE SUMMARY

Eine vollständige Spielrunde (Main Menu → World → Forschung → Planet-Dossier → Bauen) wurde über den GDScript-MCP-Bridge komplett ferngesteuert durchgespielt. Der Agent spielte Klick für Klick, mit virtuellem Maus-Move, Screenshots und Game-State-Queries.

**Ergebnis:** Das Spiel ist technisch spielbar, scheitert aber an **4 kritischen Bugs** und **8 UX-Friktionen** im Onboarding. Dazu kommen **5 MCP-Bedienungsanomalien**, die den Test-Workflow selbst erschweren.

---

## 📋 INHALT

1. [Playtest-Durchlauf (Klick-Protokoll)](#1-playtest-durchlauf)
2. [GAME-Mismatches (Bugs & UX)](#2-game-mismatches)
3. [MCP-Mismatches (Tool-Anomalien)](#3-mcp-mismatches)
4. [MCP-Playtest-Prompts](#4-mcp-playtest-prompts)
5. [Sprint-6-Empfehlung](#5-sprint-6-empfehlung)

---

## 1. PLAYTEST-DURCHLAUF

### 1.1 Session-Start

```bash
# Server-Start (manuell):
C:/.../Godot_v4.7.2-stable_win64_console.exe --path . -- --mcp --mcp-port 9090

# Client-Connect:
node -e "net.connect(9090,'127.0.0.1')"  # → CONNECTED
```

**Verbindungsaufbau:**
```
initialize(protocolVersion: "2024-11-05") → OK, 116 tools
initialized() → lifecycle ready
```

### 1.2 Main Menu → Neues Spiel

| Schritt | Tool | Parameter | Ergebnis |
|---------|------|-----------|----------|
| Menu scannen | `runtime_ux_scan` | — | Scene: `main_menu`, 6 Controls |
| NEUES SPIEL klicken | `runtime_ux_click` | `{description:"Neues Spiel"}` | `clicked:true` |

**Main-Menu-Controls:**
```
[button] "NEUES SPIEL"    int=true  dis=false
[button] "WEITER"         int=true  dis=true   ← kein Spielstand
[button] "BEENDEN"        int=true  dis=false
[label]  "SNIPWAR" / "EISEN-GRENZE"
```

### 1.3 World geladen

| Schritt | Tool | Ergebnis |
|---------|------|----------|
| Scan nach 3s | `runtime_ux_scan` | Scene: `game_view`, 13 Controls |

**World-Controls (Haupt-Buttons):**
```
PLANETEN › | TECHNOLOGIE ›                                    ← Layer-Tabs
PLANET | WERKSTATT | FORSCHUNG | ECONOMY                       ← Toolbar
FLOTTENÜBERSICHT | ◂ | UNTERWEGS: Keine aktiven Schiffe       ← Sidebar
PLANETEN: Keine ausgewählten Planeten | 6                      ← Strength
```

**Game State (Initial):**
```json
{
  "resources": {"biomass":50, "credits":100, "energy":50, "material":30, "rare":30, "volatile":30},
  "factions": {"count":0, "planets":[]},
  "ships": {"count":0},
  "dispatch": {"active":[], "pending":[]}
}
```

> ⚠️ `game_faction_query` liefert `planets:[]` — Planeten nicht via MCP abfragbar. Bug oder falscher Pfad.

### 1.4 Forschung öffnen

| Schritt | Tool | Ergebnis |
|---------|------|----------|
| FORSCHUNG klicken | `runtime_ux_click` | `clicked:true` |
| Scan | `runtime_ux_scan` | 40 Controls, FORSCHUNGSBAUM sichtbar |

**Tech-Baum (aktiv/disabliert):**
```
[ACTIVE]   Orbitales Werft-Design   10 energy
[ACTIVE]   Mech-Chassis T1          25 volatile
[ACTIVE]   Planetare Vermessung     10 rare
[DISABLED] 23 weitere Techs (keine Prärequisit-Info)
```

### 1.5 Forschung durchführen

| Schritt | Tool | Ergebnis |
|---------|------|----------|
| Klick "Orbitales Werft-Design" | `runtime_ux_click` | `clicked:true` |
| Klick "Mech-Chassis T1" | `runtime_ux_click` | `clicked:true` |

**Ressourcen nach Forschung:**
```
Vorher: E:50 C:100 M:30 R:30 V:30 B:50
Nachher: E:40 C:90  M:30 R:30 V:5  B:50
```
→ 10E + 25V abgezogen ✓, 10 Credits ✓

**ABER:** `game_research_status` zeigt `{active:[], completed:[]}` — **Bug!**

### 1.6 Panel-Schließen (PaperDossier CloseButton)

| Schritt | Tool | Ergebnis |
|---------|------|----------|
| SCHLIESSEN finden | `runtime_ux_find` | `found:true, match_score:0.75` |
| SCHLIESSEN klicken | `runtime_ux_click` | `clicked:true` — Panel manchmal noch offen |

**Problem:** Sheet-Rotation `-1.1°` versetzt Button-Position → Clicks daneben. Nach 2–3 Versuchen klappt es manchmal.

### 1.7 Sub-Tab-Wechsel (ECONOMY/WERKSTATT)

| Schritt | Tool | Ergebnis |
|---------|------|----------|
| ECONOMY klicken | `runtime_ux_click` | `clicked:true` — aber FORSCHUNGSBAUM bleibt |
| WERKSTATT klicken | `runtime_ux_click` | `clicked:true` — kein Panel-Inhalt |

**Bug:** Tab-Wechsel feuert korrekt aber Content ändert sich nicht.

### 1.8 Kamera-Panning

```javascript
// Kamera bei Start: (-6663, -6873) — viel zu weit draußen!
// 4× Drag TR→BL:
runtime_drag({from_x:850, from_y:80, to_x:100, to_y:450, duration_ms:1000})
// → Kamera: (-5618, -5828) — immer noch zu weit
// Nochmal 4× Drag:
// → Kamera: nähert sich 0, aber nie erreicht
```

**Kamera-Problem:** Startposition extrem weit entfernt. Spieler sieht nur leeren Raum.

### 1.9 Planet-Dossier (nach manuellem Kamera-Pan)

Nach ~12 Drags erreicht:

```
Scene: game_view, 139 Controls

PLANET-DOSSIER (GEÖFFNET):
  ??? (UNBEKANNT)
  Status: Neutrale Welt
  Produktion: Unbekannt (Forschungsschiff benötigt)
  Verfügbare Einheiten: 4
  Bauplätze: 2  ·  Perimeter-Slots: 2  ·  Reichweite: 150

  PLATEN-AUSBAU
  ▾  WIRTSCHAFT
    Rohstoff-Extraktor     40/15E  ·  90/5C  ·  Arb:1  [BAUEN]
    Raffinerie             30/25M  ·  90/5C  ·  Arb:2  [BAUEN]
    Handelsposten          5/20V   ·  90/5C  ·  Arb:1  [BAUEN]
    Automatisiertes Bergwerk 30/20M · 90/5C  ·  Arb:1  [BAUEN]
    Handelszentrum         50/20B  ·  90/5C  ·  Arb:1  [BAUEN]
  ▸  MILITÄR
  ▸  TECHNOLOGIE
  ▸  INFRASTRUKTUR

  GARNISONEN: 74 Planeten mit Stärke-Zahlen
  MISSION STARTEN
```

### 1.10 BAUEN-Buttons

| Schritt | Tool | Ergebnis |
|---------|------|----------|
| BAUEN-Buttons finden | `runtime_ux_scan` | 5× Button mit Text "BAUEN" |
| Click-by-text | `runtime_ux_click({description:"BAUEN"})` | Geht ins Leere (identische Labels) |
| Click-by-path | `runtime_click({path:"...@Button@351656"})` | `"Control is disabled"` obwohl `interactable:true` |

**Bug:** 5 identische "BAUEN"-Buttons: weder Text- noch Path-Klick funktioniert.

---

## 2. GAME-MISMATCHES

### 🔴 KRITISCHE BUGS (blockieren Progression)

#### BUG-G1: PaperDossier-CloseButton durch Sheet-Rotation unklickbar
- **Datei:** `scripts/ui/dossier/paper_dossier.gd:141` — `_sheet.rotation = deg_to_rad(-1.1)`
- **Ursache:** -1.1° Rotation verschiebt die Global-Position des CloseButtons
- **MCP-Symptom:** `runtime_ux_find("SCHLIESSEN")` → match_score 0.75, Click geht daneben
- **Spieler-Symptom:** ✕-Button manchmal unresponsive
- **Fix:** Rotation entfernen oder Button außerhalb des rotierten Sheets platzieren

#### BUG-G2: Sub-Tabs (PLANET/WERKSTATT/FORSCHUNG/ECONOMY) wechseln Content nicht
- **Datei:** `scripts/objects/planets/planet_network_ui.gd`
- **Ursache:** Tab-Click feuert, aber `_replace_content()` wird nicht aufgerufen
- **MCP-Symptom:** `runtime_ux_click("ECONOMY")` → klickt, aber FORSCHUNGSBAUM bleibt sichtbar
- **Spieler-Symptom:** Tab-Leiste funktionslos — muss SCHLIESSEN und neu öffnen

#### BUG-G3: Forschung instant, kein Status
- **Dateien:** `resources/config/technology_catalog_default.tres` (alle `research_time=0.0`), `scripts/state/domains/tech_domain.gd`
- **Ursache:** `TechnologyDefinition.research_time` ist durchgängig 0 → `_complete_research()` instant
- **MCP-Symptom:** `game_research_status` → `{active:[], completed:[]}` obwohl 2 Techs gekauft
- **Spieler-Symptom:** Kein Fortschritt, kein Timer, kein "In Forschung"-Indikator

#### BUG-G4: 5 identische "BAUEN"-Buttons — keiner klickbar
- **Datei:** `scripts/objects/planets/planet_network_ui.gd` → PlanetPanel UpgradeList
- **Ursache:** Alle Buttons haben Text "BAUEN" ohne Kontext. Click-by-path scheitert mit "Control is disabled"
- **MCP-Symptom:** `runtime_ux_click(text="BAUEN")` → kein Match. `runtime_click(path=...)` → disabled
- **Spieler-Symptom:** Mausklick geht, aber Screenreader/MCP-Test unmöglich

### 🟡 UX-FRIKTIONEN

| ID | Friktion | Schwere |
|----|----------|---------|
| UX-1 | "PLANET" (Toolbar) vs "PLANETEN" (Layer-Tab) — Namenskonflikt | Mittel |
| UX-2 | Forschung instant — kein Confirm-Dialog, kein Fortschritt | Hoch |
| UX-3 | 23/26 Techs disabled ohne Tooltip WARUM | Hoch |
| UX-4 | 74 Garnison-Einträge als reine Labels — nicht klickbar | Mittel |
| UX-5 | Economy öffnet als Floating-Overlay statt Dossier-Tab | Niedrig |
| UX-6 | Kamera startet bei (-6663, -6873) — Spieler sieht leeren Raum | 🔴 Kritisch |
| UX-7 | Economy zeigt "Keine laufende Produktion" für alle 5 Ressourcen | Mittel |
| UX-8 | WERKSTATT-Tab öffnet keine Inhalte (Tech-abhängig?) | Mittel |

### ✅ FUNKTIONIERT GUT

- Main Menu: Alle Buttons korrekt, WEITER disabled ohne Save
- Planet-Dossier komplett: Status, Produktion, Einheiten, Bauplätze, Kategorien
- Ressource-Abruf via `game_resources_all` → korrekte Werte
- "MISSION STARTEN" + Einheiten-Slider + Flugzeitberechnung
- 74+ Planeten-Garnison-Liste vollständig
- Dossier-Kategorien expandable (▾ WIRTSCHAFT, ▸ MILITÄR etc.)

---

## 3. MCP-MISMATCHES

### 🔴 MCP-Tool-Anomalien, die den Test-Workflow behindern

#### MCP-M1: `runtime_ux_analyze({include_visual:true})` produziert JSON zu groß
- **Symptom:** Response > 100KB bei 139 Controls → Node.js `JSON.parse` bricht ab
- **Workaround:** `runtime_ux_scan` (nur live, kein visual) funktioniert
- **Root Cause:** `include_visual:true` appended Pixel-Analyse zu jedem Control
- **Fix-Idee:** `max_controls`-Parameter oder Streaming-Response

#### MCP-M2: `game_faction_query()` liefert leeres Array trotz geladener Welt
- **Symptom:** `{count:0, planets:[]}` aber Planet-Dossier zeigt 74+ Planeten
- **Root Cause:** `mcp_gameplay_tools.gd:_faction_query()` sucht nach `get_faction()` auf `PlanetField`-Kindern — aber `PlanetField`-Kinder sind `Node2D`-Container mit Planeten-Namen, die eigentlichen Planet-Objekte liegen tiefer
- **Workaround:** `runtime_get_scene_tree` manuell parsen

#### MCP-M3: `runtime_click` auf Area2D/Node2D (keine Control) schlägt fehl
- **Symptom:** `runtime_click({path:".../ClickArea"})` → `"No click position available"`
- **Ursache:** Welt-Planeten sind Area2D → Maus-Event geht nur auf Controls
- **Workaround:** Kamera-Position + Planeten-Weltkoordinate → Screen-Koordinate → `runtime_click({x, y})`

#### MCP-M4: `runtime_eval` braucht `--mcp-developer` Flag
- **Symptom:** `{"error":"eval requires developer mode (--mcp-developer)"}`
- **Workaround:** Server-Neustart mit Flag (nicht praktikabel im laufenden Test)
- **Empfehlung:** Developer-Mode default für Test-Sessions dokumentieren

#### MCP-M5: Verbindung bricht bei Godot-Neustart ab — kein Auto-Reconnect
- **Symptom:** Nach Server-Neustart muss Node.js-Client neu verbinden
- **Workaround:** Manuelles Reconnect-Script

### 🟡 MCP-Bedienungs-Anomalien

| ID | Anomalie | Auswirkung |
|----|----------|------------|
| MCP-A1 | `runtime_ux_find` match_score 0.75 für CloseButton → unsicher ob geklickt wurde | Agent braucht Fallback-Strategie |
| MCP-A2 | Viewport-Koordinaten (960×540) ≠ Screen-Koordinaten (1280×720) — `runtime_click`-Scale verwirrend | Koordinaten-Converter nötig |
| MCP-A3 | Kein `runtime_camera_center_on`-Tool → Kamera nur via Drag bewegbar | Umständlich, 8+ Drags nötig |
| MCP-A4 | Screenshot als Async-Tool — blockiert sequentiellen Flow | `await` nötig, Response zeitverzögert |
| MCP-A5 | `runtime_mouse_move` feuert Hover, aber kein Hover-Tooltip-System im Spiel → keine Validierung möglich | Hover-Effekte nicht testbar |

---

## 4. MCP-PLAYTEST-PROMPTS

### Prompt-Set A: Quick Health Check (30s)

```
1. Verbinde mit MCP-Server auf 127.0.0.1:9090
2. initialize → initialized → runtime_mcp_status
3. runtime_ux_scan → prüfe scene=main_menu|game_view
4. game_resources_all → prüfe credits≥90, energy≤50
Erwartet: Verbindung OK, Scene bekannt, Ressourcen plausibel
```

### Prompt-Set B: Main Menu → World (60s)

```
1. runtime_ux_click("Neues Spiel")
2. Warte 3s, dann runtime_ux_scan → erwarte scene=game_view
3. Prüfe: Controls enthalten PLANET, WERKSTATT, FORSCHUNG, ECONOMY
4. Prüfe: Keine aktiven Schiffe, Keine ausgewählten Planeten
```

### Prompt-Set C: Forschungs-Flow (90s)

```
1. runtime_ux_click("FORSCHUNG")
2. runtime_ux_scan → zähle TechNode-Controls
3. Finde ersten ACTIVE TechNode → klicken
4. game_resources_all → prüfe ob Kosten abgezogen
5. game_research_status → prüfe ob active NICHT leer (BUG wenn leer!)
6. runtime_ux_click("SCHLIESSEN") → prüfe ob Panel zu
```

### Prompt-Set D: Kamera & Planet (120s)

```
1. runtime_inspect_node("/root/World/MapCamera") → lese position
2. Wenn |position| > 5000: runtime_drag(TR→BL) mehrfach
3. Nach jedem Drag: prüfe position-Delta
4. Wenn Kamera in Planet-Nähe: runtime_ux_scan → erwarte > 13 Controls
5. Finde Planet-Dossier-Texte: "Status:", "Produktion:", "Bauplätze:"
```

### Prompt-Set E: Full Playthrough (5 min)

```
Chain: step1_main_menu.js → step2_panels.js → chain_camera_pan.js → step4_planet_click.js
Erwartete Ergebnisse pro Step:
  step1: scene=game_view, resources init
  step2: 2 techs aktiv, resources reduziert
  chain: Kamera bei |pos| < 3000
  step4: 100+ Controls, Planet-Dossier offen
Fehlerprotokoll: Alle game_research_status-Checks, CloseButton-Versuche
```

---

## 5. SPRINT-6-EMPFEHLUNG

Basierend auf Playtest-Priorität:

| # | Story | Begründung |
|---|-------|------------|
| **S4** | Kamera zentriert auf Homeworld | Ohne das sieht Spieler NICHTS — höchste Prio |
| **S7** | CloseButton-Fix (Rotation weg) | Blockiert Panel-Schließen |
| **S8** | Sub-Tab-Wechsel | Blockiert Navigation zwischen Panels |
| **S1** | Forschung mit Dauer + Indikator | Research_time > 0, Ring-Indikator |
| **S2** | Steuerungs-Tooltips + Hotkeys | Jeder Button braucht Hotkey |
| **S3** | Gratis-Scout Drag & Drop | Erste Spieler-Aktion ermöglichen |
| **S5** | Unbewohnte Planeten | Missions-Vielfalt |
| **S6** | Control-Felder/Panel-Zonen | UI-Overlap beseitigen |
| **S9** | Max 1 Auftrag/Planet | Dispatch-Limit |

**Atomare Commits:**
```
fix: camera starts centered on homeworld with neighbor planets in FoV
fix: dossier close-button and sub-tab switching
feat: timed research with planet indicator rings + game_research_status fix
feat: input hint overlay with hotkey context system
feat: free starter scout ship with drag-and-drop dispatch
feat: uninhabited planet type and starting neighborhood mix
feat: control-field panel zones — non-overlapping layout
feat: max one active dispatch order per planet
```