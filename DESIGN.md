# SnipWar Design Contract

## Aktueller Scope

SnipWar ist momentan ein spielbarer Overworld-Vertical-Slice: zehn deterministisch verteilte Planeten, logische Planetenzähler, Zielauswahl, Flugzeitvorschau, sichtbarer Transit und Ankunft. Eine taktische Gefechtsansicht und Mech-Gameplay kommen später.

## Abgeschlossene Entscheidungen

- **Zielauswahl:** Das Ziel wird vor dem Senden im Planeten-Tab gewählt. Der Sendeknopf startet danach direkt den Transit; es gibt keinen zweiten Bestätigungsschritt.
- **Routenregel:** Die aktive `ScenarioDefinition` trägt die Routenregel explizit: `default` verwendet `all_planets`, `wide` verwendet `neighbors_only`. Jeder erlaubte Transit läuft trotzdem über das AStar2D-Netz aus benachbarten Planeten; direkte Luftlinien sind nur der Fallback bei einem ungültigen Netzpunkt.
- **Waypoint-Katalog:** `NavigationConfig` referenziert einen typisierten `NavigationWaypointCatalog`. Der Katalog wählt deterministisch pro Layoutkante eine validierte Moon-/Comet-Definition; Maps dürfen eigene Kataloge und Cadences verwenden, ohne `NavigationField`-Code zu ändern.
- **Routenvisualisierung:** Route color, Alpha-Puls, Pulsfrequenz und Linienbreite liegen im `UIThemeConfig`; `PlanetNetwork` zeichnet daraus dieselbe ausgewählte AStar-Route, die Preview und Transit verwenden.
- **Flugzeit:** Die Vorschau reagiert sofort auf die Slider-Menge und verwendet die Länge des Navigationspfads statt der direkten Luftlinie. Das MVP verwendet das glatte, reskalierbare Modell:

  ```text
  (Distanz / 100) × 8 × (1 + 0.05 × sqrt(max(Einheiten − 1, 0)))
  ```

  Die Preflight-Suite deckt Basiswert, Mengenlast und monotones Wachstum ab.
- **Cluster:** Largest-first-Packung mit `K=1`, `M=5`, `L=100`; zum Beispiel `7 → M + K + K`. Alle Gruppen starten im selben Frame in einer deterministischen V-/Keilformation. Cluster sind nur während des Transits sichtbar; ruhende Einheiten erscheinen ausschließlich als Zähler.
- **Überlappung:** Die Formation verwendet den größten sichtbaren Cluster der Sendung und einen Sicherheitsfaktor von `0.85` des Durchmessers. Preflight prüft reale Offsets und Paarabstände mit drei Transit-Clustern.
- **Planetendetails:** Seed-basiert, maximal drei logische Details. Toxic garantiert Satellit und Asteroidengürtel und kann einen Kometen erhalten. Jede Detaildefinition referenziert ein `PlanetDetailFidelity`-Profil für per-Detail Orbitbewegung (`full`, `throttled`, `static`); Winkelgeschwindigkeit, Phase und Alpha werden nicht aus einer globalen Mittelung abgeleitet. Der ungeplante cyanfarbene Orbitalring ist entfernt.
- **Stil:** Cell-shaded Paperclip-Comic mit klaren Silhouetten, Beleuchtung und Schattierung. K/M/L sind generische, erweiterbare SVG-Assets mit `Attachments` für spätere Objekte.
- **Präsentation:** Der aktuelle technische Raum ist `960×540` mit Canvas-Item-Stretch und einem `1280×720`-Fenster-Override. Das UI nutzt ein konfiguriertes responsives Panel; Hintergrund- und Meteor-Tuning liegen in eigenen Resources. 4K bleibt eine spätere Präsentationsstufe, keine MVP-Anforderung.
- **Szenario-/Kartenschicht:** `MapDefinition` bündelt WorldConfig, PlanetCatalog, Größenprofile und Navigation; `ScenarioDefinition` ergänzt Routenregel, Transit- und Präsentations-Configs. `ScenarioCatalog` wählt vor dem Eintritt des PlanetField einen aktiven Datensatz. Der MVP enthält `default` mit Laufzeit-Seed und Standard-Waypoint-Katalog sowie `wide`/`Frontier Ring` mit festem Seed, eigener Waypoint-Cadence und `neighbors_only`; ein Katalogwechsel im laufenden PlanetField ist noch nicht vorgesehen.
- **Besitz und Factions:** `GameState` (Autoload) ist die einzige Quelle für Planetenbesitz und Factions. Der aktive Katalog seedet genau einen Player-Startplaneten (`Ocean`, Faction `a`) und einen CPU-Startplaneten (`Paper`, Faction `b`); die übrigen acht Planeten starten neutral. Nach der finalen Layout-Größenzuweisung erhalten alle Planeten eine größenabhängige Anfangsgarnison aus `PlanetSizeProfile.starting_workers` (XL=6, L=4, variable=2). Änderungen laufen über das `faction_changed`-Signal. Die Faction-Namen `a`/`b`/`neutral` aus dem Katalog bleiben der Datenvertrag; `player`/`cpu` sind als semantische Aliase vorgesehen, solange kein Gameplay davon abhängt.
- **Conflict-Vertical-Slice:** Jede Kampf-Transitgruppe trägt ihre `source_faction`. Bei Ankunft verstärkt eine gleiche Faction den Zielplaneten; eine kleinere oder gleich große Invasion wird von den Verteidigern abgewehrt; eine größere Invasion reduziert die Verteidiger auf null, übernimmt den Planeten und lässt die Überlebenden als neue Garnison zurück. Der Ownership-Wechsel läuft ausschließlich über `GameState.faction_changed`.

- **Ressourcen-Verteilung:** Ressourcen sind unsichtbare, datengetriebene `GameResource`-Objekte aus einem `ResourcePool`. Beim Spielstart dealt `GameState` sie seed-deterministisch über den aktiven Katalog: Startplaneten (Homeworlds) erhalten garantiert unterschiedliche Ressourcen, der Rest wird rotierend ausbalanciert (jede Ressource kommt ±1 gleich oft vor). Es gibt keine feste Planet-→Ressource-Zuordnung; Maps können über `MapDefinition.resource_pool` eigene Pools referenzieren. Die Produktionslogik bleibt späterer Ausbau.
- **Kampf-Resolve:** Es gibt bewusst noch keine feste Stärkeformel. Elemente, Waffentypen, Panzerung und weitere Tech-Tree-Faktoren werden als datengetriebene Modifikatoren ergänzt, bevor ein deterministisches Resolve festgelegt wird.
- **Skalierung:** Die Karten-Generation (Layout, Nachbarschaften, Waypoint-Netz) ist O(n) in der Planetenanzahl; Preflight verifiziert Layout, Routen und Ressourcenverteilung bis 1500 Planeten.

## Validierter Vertical Slice

`Slider → Live-Flugzeit/Ziel → Senden → Quelle reduzieren → Transitformation → Ziel erhöhen → Transit-Assets entfernen` ist durch `scripts/preflight.gd` und den Headless-Main-Scene-Smoke-Test abgedeckt.

## Bewusst aus dem MVP herausgenommen

- **Render-Budget-Kompression:** Wiederholte Sterne und Staub werden über `MultiMeshInstance2D` gebatcht; Falten und Grain werden über konfigurierbare Alpha-Buckets mit `draw_multiline()` zusammengefasst. Die Bucket-Anzahl begrenzt den Fidelity-/Draw-Call-Trade-off, die wesentlichen Aufträge bleiben weitgehend unabhängig von Stern-/Staubdichte und werden bei Viewport-Größenänderung neu aufgebaut. Die konkrete GPU-Messung bleibt zielgeräteabhängig.
- **4K-Kamera und Gefechtsansicht** sowie Mech-Klassen, Loadouts, Ressourcenrisiko und Siegbedingungen bleiben spätere Ausbaustufen.
