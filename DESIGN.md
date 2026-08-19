# SnipWar Design Contract

## Aktueller Scope

SnipWar ist momentan ein spielbarer Overworld-Vertical-Slice: zehn deterministisch verteilte Planeten, logische Planetenzähler, Zielauswahl, Flugzeitvorschau, sichtbarer Transit und Ankunft. Eine taktische Gefechtsansicht und Mech-Gameplay kommen später.

## Abgeschlossene Entscheidungen

- **Zielauswahl:** Das Ziel wird vor dem Senden im Planeten-Tab gewählt. Der Sendeknopf startet danach direkt den Transit; es gibt keinen zweiten Bestätigungsschritt.
- **Flugzeit:** Die Vorschau reagiert sofort auf die Slider-Menge. Das MVP verwendet das glatte, reskalierbare Modell:

  ```text
  Distanz × (1 + 0.12 × sqrt(max(Einheiten − 1, 0)))
  ```

  Die Preflight-Suite deckt Basiswert, Mengenlast und monotones Wachstum ab.
- **Cluster:** Largest-first-Packung mit `K=1`, `M=5`, `L=100`; zum Beispiel `7 → M + K + K`. Alle Gruppen starten im selben Frame in einer deterministischen V-/Keilformation. Cluster sind nur während des Transits sichtbar; ruhende Einheiten erscheinen ausschließlich als Zähler.
- **Überlappung:** Die Formation verwendet den größten sichtbaren Cluster der Sendung und einen Sicherheitsfaktor von `0.85` des Durchmessers. Preflight prüft reale Offsets und Paarabstände mit drei Transit-Clustern.
- **Planetendetails:** Seed-basiert, maximal drei logische Details. Toxic garantiert Satellit und Asteroidengürtel und kann einen Kometen erhalten. Der ungeplante cyanfarbene Orbitalring ist entfernt.
- **Stil:** Cell-shaded Paperclip-Comic mit klaren Silhouetten, Beleuchtung und Schattierung. K/M/L sind generische, erweiterbare SVG-Assets mit `Attachments` für spätere Objekte.
- **Präsentation:** Der aktuelle technische Raum ist `960×540` mit Canvas-Item-Stretch und einem `1280×720`-Fenster-Override. 4K bleibt eine spätere Präsentationsstufe, keine MVP-Anforderung.

## Validierter Vertical Slice

`Slider → Live-Flugzeit/Ziel → Senden → Quelle reduzieren → Transitformation → Ziel erhöhen → Transit-Assets entfernen` ist durch `scripts/preflight.gd` und den Headless-Main-Scene-Smoke-Test abgedeckt.

## Bewusst aus dem MVP herausgenommen

- **Render-Budget-Kompression:** Ein Draw-Call-Median mit `250/225`-Hysterese wurde als mögliche spätere Messregel beschrieben, ist aber keine aktive Laufzeitlogik. Die aktuelle feste K/M/L-Packung und die Transit-Sichtbarkeit sind einfacher und ausreichend; eine spätere Implementierung muss auf dem Zielgerät kalibriert werden.
- **4K-Kamera, Gefechtsansicht, Mech-Klassen, Loadouts, Ressourcenrisiko und Siegbedingungen** bleiben spätere Ausbaustufen.

## Nächste Ausbaustufen

1. Gefechtsansicht und Mech-Gameplay.
2. Ressourcen, Schaden, Eroberung und Siegbedingungen.
3. Objekt-Upgrades für Cluster (`Attachments`).
4. Zielgeräte-Kalibrierung für die optionale Render-Budget-Kompression.
5. 4K-UI-, VFX- und Kamera-Pass.

## Prüfungen

```text
C:/Users/Vannon/Desktop/godu/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://scripts/preflight.gd
C:/Users/Vannon/Desktop/godu/Godot_v4.7.2-stable_win64_console.exe --headless --path . --quit-after 2
```
