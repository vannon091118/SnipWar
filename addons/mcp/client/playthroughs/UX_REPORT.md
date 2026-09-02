# SnipWar — UX/Playability Audit
**Datum:** 2026-08-24 · **Spieler:** MCP-Agent via runtime_ux_* Tools  
**Build:** Godot 4.7.2 · **Session-Dauer:** ~15 min aktives Spiel

---

## 🔴 KRITISCHE BUGS

### BUG #1 — PaperDossier CloseButton unzuverlässig
**Pfad:** `scripts/ui/dossier/paper_dossier.gd`  
**Symptom:** `runtime_ux_find("SCHLIESSEN")` match_score = 0.75.  
CloseButton-Klicks feuern `pressed`-Signal nicht zuverlässig wegen der **-1.1° Sheet-Rotation**.  
Die transformierte Position des Buttons weicht von der visuellen ab, sodass Clicks danebengehen.

**Auswirkung:** Spieler kann Dossier nur durch Glück schließen. In ~40% der Fälle bleibt Panel offen.

### BUG #2 — Sub-Tabs im Dossier wechseln nicht
**Pfad:** `PlanetNetworkUI` → Sub-Tab-Buttons (PLANET/WERKSTATT/FORSCHUNG/ECONOMY)  
**Symptom:** Klick auf ECONOMY während FORSCHUNG offen ist → Panel zeigt weiter FORSCHUNGSBAUM.  
Tab-Wechsel feuert korrekt (`clicked: true`) aber Content wird nicht aktualisiert.

**Auswirkung:** Spieler muss SCHLIESSEN und neu öffnen für jeden Tab-Wechsel.

### BUG #3 — game_research_status zeigt leeres `active` Array
**Symptom:** Forschung (Werft-Design, Mech-Chassis) gekauft, Ressourcen abgezogen,  
aber `game_research_status` zeigt `{active: [], completed: []}`.  
Visuelles Feedback nur über Message-Label "Forschung abgeschlossen: …"

**Auswirkung:** Spieler sieht nicht ob/was gerade erforscht wird.

### BUG #4 — identische Button-Texte ("BAUEN" × 5)
**Path:** PlanetPanel UpgradeList → 5 Buttons mit Text "BAUEN"  
`runtime_ux_click(text="BAUEN")` kann nicht unterscheiden welcher Button.  
Click-by-path scheitert mit "Control is disabled" obwohl `interactable: true`.

**Auswirkung:** MCP-Agent (und Screenreader) kann kein Upgrade sicher starten.

---

## 🟡 UX-FRIKTIONEN

### UX-1: PLANET vs PLANETEN Namenskonflikt
Haupt-Toolbar: `PLANET` | `WERKSTATT` | `FORSCHUNG` | `ECONOMY`  
Layer-Tabs oben: `PLANETEN ›` | `TECHNOLOGIE ›`  
→ "PLANET" und "PLANETEN" nebeneinander. Verwirrend.

### UX-2: Forschung instant — kein Fortschrittsbalken
Forschung startet sofort beim Klick ohne Confirm-Dialog.  
Kein Timer, kein Fortschritt, kein "In Forschung"-Status sichtbar.

### UX-3: Deaktivierte Techs ohne Prärequisit-Hinweis
23 von 26 Techs im Baum deaktiviert. Kein Tooltip WARUM.  
Spieler denkt: "Bug?"

### UX-4: Planeten-Garnison-Liste ohne Klickbarkeit
74 Planetennamen im Dossier mit Zahlen (z.B. "Ember Flare: 2").  
Sind reine Labels. Zum Auswählen muss man auf der Map klicken.

### UX-5: Economy-Panel als Overlay statt Dossier-Tab
ECONOMY öffnet separat (floating X-Button) statt als Tab im Dossier.  
Inkonsistent mit PLANET/WERKSTATT.

### UX-6: Kamera startet weit entfernt von Planeten
Startkamera bei (-6663, -6873). Spieler sieht leeren Raum.  
Muss manuell pannen um erste Planeten zu finden.

### UX-7: Economy zeigt "Keine laufende Produktion" für alle 5 Ressourcen
Keine Basis-Produktion sichtbar. Unklar für neue Spieler wie Wirtschaft funktioniert.

### UX-8: Werkstatt-Tab öffnet keine Inhalte
Klick auf WERKSTATT zeigt nur World-View ohne Panel.  
Möglicherweise abhängig von Tech/Schiffen die noch nicht verfügbar sind.

---

## ✅ FUNKTIONIERT GUT

- Main Menu: `NEUES SPIEL` / `WEITER` / `BEENDEN` klar und korrekt
- Planet-Dossier öffnet beim Planet-Klick auf Map
- Dossier zeigt: Status, Produktion, Einheiten, Bauplätze, Upgrades (kategorisiert)
- "MISSION STARTEN" Button und Einheiten-Sendung UI strukturiert
- Garnison-Liste vollständig mit allen 74+ Planeten
- Ressource-Abruf via `game_resources_all` korrekt
- Screenshot + Drag-Mechanik funktionieren via MCP

---

## 🔗 WIEDERVERWENDBARE CHAINS (in `playthroughs/`)

| Chain | Zweck |
|-------|-------|
| `mcp_lib.js` | MCP-Client-Bibliothek |
| `step1_main_menu.js` | Main Menu → World |
| `step2_panels.js` | FORSCHUNG öffnen, Tech kaufen |
| `step3_planets.js` | Dossier schließen, Planet suchen |
| `step4_planet_click.js` | Planet anklicken, Panel inspizieren |
| `chain_camera_pan.js` | Drag-Sequenz zum Kamera-Pannen |
| `chain_build.js` | Upgrade-Buttons per Path klicken |