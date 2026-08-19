# SnipWar Design Contract

## Aktueller Scope

SnipWar ist momentan ein spielbarer Overworld-Vertical-Slice: zehn deterministisch verteilte Planeten, logische Planetenzähler, Zielauswahl, Flugzeitvorschau, sichtbarer Transit und Ankunft. Eine taktische Gefechtsansicht und Mech-Gameplay kommen später.

## Abgeschlossene Entscheidungen

- **Zielauswahl:** Das Ziel wird vor dem Senden im Planeten-Tab gewählt. Der Sendeknopf startet danach direkt den Transit; es gibt keinen zweiten Bestätigungsschritt.
- **Routenregel:** Das MVP verwendet `all_planets`: Jeder andere Planet darf gewählt werden; Nachbarlinien bleiben räumliche Orientierung. `neighbors_only` ist als konfigurierbare Regel für spätere Szenarien vorgesehen. Jede Auswahl läuft trotzdem über das AStar2D-Netz aus benachbarten Planeten und deterministischen Mond-/Kometen-Wegpunkten; direkte Luftlinien sind nur der Fallback bei einem ungültigen Netzpunkt.
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

## Validierter Vertical Slice

`Slider → Live-Flugzeit/Ziel → Senden → Quelle reduzieren → Transitformation → Ziel erhöhen → Transit-Assets entfernen` ist durch `scripts/preflight.gd` und den Headless-Main-Scene-Smoke-Test abgedeckt.

## Bewusst aus dem MVP herausgenommen

- **Render-Budget-Kompression:** Ein Draw-Call-Median mit `250/225`-Hysterese ist als mögliche spätere Messregel beschrieben, aber keine aktive Laufzeitlogik. Die feste K/M/L-Packung und die Transit-Sichtbarkeit sind für das MVP ausreichend; eine spätere Implementierung muss auf dem Zielgerät kalibriert werden.
- **4K-Kamera und Gefechtsansicht** sowie Mech-Klassen, Loadouts, Ressourcenrisiko und Siegbedingungen bleiben spätere Ausbaustufen.
