# SnipWar Design Contract

## Aktueller Scope

SnipWar ist momentan ein spielbarer Overworld-Vertical-Slice: zehn deterministisch verteilte Planeten, logische Planetenzähler, Zielauswahl, Flugzeitvorschau, sichtbarer Transit und Ankunft. Eine taktische Gefechtsansicht und Mech-Gameplay kommen später.

## Abgeschlossene Entscheidungen

- **Zielauswahl:** Das Ziel wird vor dem Senden im Planeten-Tab gewählt. Der Sendeknopf startet danach direkt den Transit; es gibt keinen zweiten Bestätigungsschritt.
- **Routenregel:** Die aktive `ScenarioDefinition` trägt die Routenregel explizit: `default` verwendet `all_planets`, `wide` verwendet `neighbors_only`. Jeder erlaubte Transit läuft trotzdem über das AStar2D-Netz aus benachbarten Planeten; direkte Luftlinien sind nur der Fallback bei einem ungültigen Netzpunkt.
- **Waypoint-Katalog:** `NavigationConfig` referenziert einen typisierten `NavigationWaypointCatalog`. Der Katalog wählt deterministisch pro Layoutkante eine validierte Moon-/Comet-Definition; Maps dürfen eigene Kataloge und Cadences verwenden, ohne `NavigationField`-Code zu ändern.
- **Flugzeit:** Die Vorschau reagiert sofort auf die Slider-Menge und verwendet die Länge des Navigationspfads statt der direkten Luftlinie. Das MVP verwendet das glatte, reskalierbare Modell:

  ```text
  (Distanz / 100) × 8 × (1 + 0.05 × sqrt(max(Einheiten − 1, 0)))
  ```

  Die Preflight-Suite deckt Basiswert, Mengenlast und monotones Wachstum ab.
- **Cluster:** Largest-first-Packung mit `K=1`, `M=5`, `L=100`; zum Beispiel `7 → M + K + K`. Alle Gruppen starten im selben Frame in einer deterministischen V-/Keilformation. Cluster sind nur während des Transits sichtbar; ruhende Einheiten erscheinen ausschließlich als Zähler.
- **Überlappung:** Die Formation verwendet den größten sichtbaren Cluster der Sendung und einen Sicherheitsfaktor von `0.85` des Durchmessers. Preflight prüft reale Offsets und Paarabstände mit drei Transit-Clustern.
- **Planetendetails:** Seed-basiert, maximal drei logische Details. Toxic garantiert Satellit und Asteroidengürtel und kann einen Kometen erhalten. Der ungeplante cyanfarbene Orbitalring ist entfernt.
- **Stil:** Cell-shaded Paperclip-Comic mit klaren Silhouetten, Beleuchtung und Schattierung. K/M/L sind generische, erweiterbare SVG-Assets mit `Attachments` für spätere Objekte.
- **Präsentation:** Der aktuelle technische Raum ist `960×540` mit Canvas-Item-Stretch und einem `1280×720`-Fenster-Override. Das UI nutzt ein konfiguriertes responsives Panel; Hintergrund- und Meteor-Tuning liegen in eigenen Resources. 4K bleibt eine spätere Präsentationsstufe, keine MVP-Anforderung.
- **Szenario-/Kartenschicht:** `MapDefinition` bündelt WorldConfig, PlanetCatalog, Größenprofile und Navigation; `ScenarioDefinition` ergänzt Routenregel, Transit- und Präsentations-Configs. `ScenarioCatalog` wählt vor dem Eintritt des PlanetField einen aktiven Datensatz. Der MVP enthält `default` mit Laufzeit-Seed und Standard-Waypoint-Katalog sowie `wide`/`Frontier Ring` mit festem Seed, eigener Waypoint-Cadence und `neighbors_only`; ein Katalogwechsel im laufenden PlanetField ist noch nicht vorgesehen.

## Validierter Vertical Slice

`Slider → Live-Flugzeit/Ziel → Senden → Quelle reduzieren → Transitformation → Ziel erhöhen → Transit-Assets entfernen` ist durch `scripts/preflight.gd` und den Headless-Main-Scene-Smoke-Test abgedeckt.

## Bewusst aus dem MVP herausgenommen

- **Render-Budget-Kompression:** Wiederholte Sterne und Staub werden über `MultiMeshInstance2D` gebatcht; Falten und Grain werden je Stilfarbe über `draw_multiline()` zusammengefasst. Die Anzahl der wesentlichen Draw-Aufträge bleibt damit weitgehend unabhängig von Stern-/Staubdichte und wird bei Viewport-Größenänderung neu aufgebaut. Die konkrete GPU-Messung bleibt zielgeräteabhängig.
- **4K-Kamera und Gefechtsansicht** sowie Mech-Klassen, Loadouts, Ressourcenrisiko und Siegbedingungen bleiben spätere Ausbaustufen.
