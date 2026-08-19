---
konzept: SnipWar Mech Dispatch
slug: snipwar-mech
datum: 2026-08-19
status: recherchiert
quelle: direkt
tags: [#snipwar, #mech, #hybrid, #ui, #skalierung]
---

# SnipWar // Dispatch Protocol

## 🎯 Kern-Idee

SnipWar wird als Hybrid aus strategischer Galaxiekarte und späterer taktischer Gefechtsansicht schrittweise aufgebaut. Die 4K-Ausgabe ist ein späteres Präsentations- und Qualitätsziel; die visuelle Identität ist vorläufig ein skalierbarer Paperclip-/Clip-Art-Comic mit klaren Silhouetten und modularen Assets.

Der erste spielbare Befehl ist kein sofortiger Kampf, sondern ein sichtbarer Truppenversand: Menge wählen, Flugzeit und Weg lesen, senden, Abflug beobachten, Ankunft verbuchen.

## 🧩 Große Bestandteile

- **Mengenwahl:** Ein Slider reicht von `1` bis zur aktuell verfügbaren logischen Menge.
- **Live-Vorschau:** Sobald sich die Slider-Menge ändert, werden Flugzeit und Weg aktualisiert; größere Verbände fliegen langsamer.
- **Dispatch:** „Senden“ packt die gewählte logische Menge largest-first in K/M/L-Cluster-Assets und startet alle Gruppen gleichzeitig in einer route-deterministischen Formation zum Ziel.
- **Zustandslogik:** Beim Start wird der Quellzähler um die vollständige Menge reduziert; bei Ankunft steigt der logische Zielzähler um genau diese Menge.
- **Darstellung:** Drei feste Clusterstufen repräsentieren `K=1`, `M=5` oder `L=100` logische Einheiten; eine Sendung wird largest-first gepackt, z. B. `7 → M + K + K`, und alle sichtbaren Gruppen bleiben als V-/Keilformation geordnet.
- **Zeitmodell:** Ausbalanciertes, einfach parametrisiertes Modell — nicht zu komplex —, das sich bei Bedarf neu skalieren lässt; konkrete Koeffizienten bleiben Testwerte.
- **Baufolge:** Erst Slider und Vorschau, dann Versand und Zählerereignisse, dann sichtbare Transit-Assets, danach Gefechtsansicht und 4K-Veredelung.
- **Stil:** Cell-Shaded-Paperclip-Look mit starkem Fokus auf Beleuchtung und Schattierung; Mechs sind aktuell noch nicht implementiert — zuerst nur Overworld-Layer und Mechanik-Tests.

## 🧭 Drift-Tickets

- [ ] [Sichtbarkeitsbudget messen](drift-log/2026-08-19-snipwar-mech-budget-drift.md): Draw-Call-Median mit 250/225-Schwellen und minimaler Hysterese.

## ❓ Offen

- [ ] Testfälle für die Balanced-Flugzeitformel definieren.
- [ ] Festlegen, ob das Ziel vor dem Senden gewählt wird oder Teil des Sendeschritts ist.
- [ ] 4K-Zielauflösung, UI-Dichte und Kamera-Skalierung als spätere Präsentationsspezifikation definieren.

## 🎯 Entscheidungen

| Thema | Wahl | Warum | Datum |
|---|---|---|---|
| Spielstruktur | Hybrid aus Karte und Gefecht | Strategie bleibt sichtbar, Gefechte können als nächster Layer wachsen. | 2026-08-19 |
| Ausbau | Stück für Stück / vertikale Slices | Jede Stufe soll einen testbaren Befehlsfluss liefern. | 2026-08-19 |
| 4K | Späteres Endziel | Vision bleibt erhalten, ohne den Prototyp als fertiges 4K-Spiel auszugeben. | 2026-08-19 |
| Mengensteuerung | Slider `1..verfügbar` | Direkte, lesbare Auswahl der Versandmenge. | 2026-08-19 |
| Vorschau | Sofort nach Mengenänderung | Die Kosten größerer Verbände werden vor dem Senden sichtbar. | 2026-08-19 |
| Flugzeit | Balanced, einfach parametrisiert | Einfach zu kalibrieren und bei Bedarf neu skalierbar; keine überkomplexe Formel. | 2026-08-19 |
| Zähler | Ein logischer Zähler pro Planet | Sichtbare Marker dürfen komprimieren, ohne Spielzustand zu verlieren. | 2026-08-19 |
| Sichtbarkeit | Höchstens 100 Assets | Große Mengen bleiben lesbar und performant darstellbar. | 2026-08-19 |
| Kompression | Feste K/M/L-Schwellen | Logische Mengen werden largest-first in K=1, M=5 und L=100 generische Assets gepackt; alle Gruppen starten gleichzeitig in Formation. | 2026-08-19 |
| Stil | Cell-Shaded-Paperclip | Beleuchtung und Schattierung sind wichtiger als die Wahl zwischen Paperclip und Papercut; Mechs kommen erst später. | 2026-08-19 |

## 🔍 Recherche

| Frage | Antwort | Quelle | Datum |
|---|---|---|---|
| Eignen sich SVGs für skalierbare Comic-Assets? | Godot 4.7 importiert SVG als automatisch skalierbare Textur für UI und 2D. `base_scale` kann die Texturgröße steuern. | [ResourceImporterSVG](https://docs.godotengine.org/en/4.7/classes/class_resourceimportersvg.html) | 2026-08-19 |
| Wie bleibt SVG bei verschiedenen Auflösungen scharf? | SVG kann als `DPITexture` importiert und zur Laufzeit passend zum Oversampling-Faktor erneut rasterisiert werden. Komplexe SVGs haben eingeschränkte Unterstützung; Text sollte in Pfade umgewandelt werden. | [Importing images](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html) | 2026-08-19 |
| Wie reagiert ein Slider auf Live-Vorschau? | `Range.value_changed` wird bei einem Slider kontinuierlich während des Ziehens ausgelöst; aufwendige Weg-/Vorschau-Berechnungen sollten deshalb billig bleiben oder gedrosselt werden. | [Range](https://docs.godotengine.org/en/4.7/classes/class_range.html) | 2026-08-19 |
| Wie können dynamische Transit-Assets bewegt werden? | `create_tween()` und `tween_property()` eignen sich für unbekannte Zielwerte; `finished` signalisiert die Ankunft. Ein an einen Node gebundener Tween wird beim Entfernen des Nodes automatisch beendet. | [Tween](https://docs.godotengine.org/en/4.7/classes/class_tween.html) | 2026-08-19 |

## 📊 IST-Vergleich

| Aspekt | IST | SOLL | Gap |
|---|---|---|---|
| Weltstruktur | Planetennetz und Worker-/Zähler-Prototyp laut bisherigem Projektkontext | Hybrid-Befehlskette mit taktischer Transitentscheidung | Slider, Vorschau und Ereignisfluss ergänzen |
| Einheitenbewegung | Logische Planetenzähler und gespeichertes Ziel als Zwischenstand | Sichtbare Assets erscheinen nur im Transit; Ankunft löst Zielzähler aus und entfernt das Asset | Transit-Lifecycle definieren |
| Darstellung | Kleine 2D-Assets und begrenzte sichtbare Instanzen | SVG-taugliche Comic-Silhouetten mit Kompression bis 100 Marker | Asset-Pipeline und Gruppierungsregeln festlegen |
| Auflösung | Prototypbasis | Spätere 4K-Präsentation | Kamera-, UI- und Oversampling-Spezifikation fehlt |

## 📌 Nächste Schritte

- [ ] Ein kleines Zahlen-Set für Distanz, Menge und erwartete Flugzeit als Design-Tabelle festlegen.
- [ ] Einen vertikalen Slice „Slider → Live-Vorschau → Senden → Ankunft“ als Konzeptabnahme definieren.
- [ ] K/M/L-Clusterassets anhand sichtbarer Beispiele `1`, `5` und `100` weiter ausarbeiten und Attachment-Objekte definieren.
- [ ] Cell-Shaded-Paperclip-Regeln für Kontur, Beleuchtung und Schattierung beschreiben.
- [ ] Erst danach die technische Umsetzung in Godot planen.
