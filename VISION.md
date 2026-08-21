# SnipWar — Vision

Dieses Dokument beschreibt die gewünschte Richtung von SnipWar. Es ist kein aktueller Feature-Vertrag. Der Abschnitt **Verifizierter Ausgangspunkt** beschreibt ausschließlich Systeme, die im Code vorhanden sind; die folgenden Layer sind Zielbild und müssen vor ihrer Umsetzung als eigene Contracts präzisiert werden.

## Verifizierter Ausgangspunkt

Der aktuelle Build besitzt bereits einen strategischen Overworld-Kern:

- zehn Planet-Definitionen mit zwei Homeworlds und acht neutralen Welten
- seed-deterministische Layouts, Größenprofile, Details, Waypoints und Ressourcenverteilung
- Größenprofile mit unterschiedlichen Spawnintervallen, Startgarnisonen, Bauplätzen und Produktionsbasen
- `GameState` als autoritative Quelle für Besitz, Ressourcen, Forschung, Discovery, Scan-Intel, Upgrades und Ship-Builder-Zustand
- sichtbare Planetennachbarschaft, AStar2D-Routen und gemeinsame Flugzeitvorschau/Transitpfade
- missionsabhängiger Transit für Military, Colony, Cargo und Collect
- einfacher Resolve bei militärischer Ankunft: Verstärkung, Abwehr oder Besitzwechsel
- Economy- und Gather-Timer, CPU-Dispatch-AI, Scouts und EventLog
- vier Planet-Upgrade-Zweige, planetare und globale Technologien sowie ein UI-Ship-Builder

Der aktuelle Ship Builder erzeugt noch keine einsatzfähige Kampf- oder Expeditionsflotte. Er verwaltet Assemblies als Inventar- und Anzeigezustand. Der Scout ist der einzige aktiv gebaute und fliegende Schiffstyp.

## Der gewünschte Spielkreislauf

Die langfristige Richtung ist ein 4X-artiger Kreislauf:

```text
Wirtschaft → Expansion → Kontakt → Flottenkonflikt → Eroberung → veränderter Ressourcenfluss
```

Dieser Kreislauf ist noch nicht vollständig im Code geschlossen. Ressourcen, Forschung, Besitz und einfache Missionen sind vorhanden; Flottenkampf, planetare Eroberung und Siegbedingungen fehlen.

## Layer 1 — Strategische Overworld

Layer 1 soll die dauerhaft spielbare Entscheidungsebene bleiben.

### Ressourcen und Planetentypen

Der Code verteilt aktuell fünf Ressourcen aus einem globalen `ResourcePool` seed-deterministisch über den aktiven Katalog. Die beiden Homeworlds erhalten unterschiedliche Ressourcen; die übrige Verteilung ist ausgeglichen. Eine vorhandene Hilfsmethode ordnet Planetentypen thematischen Ressourcen zu, wird für die tatsächliche Verteilung und Produktion aber nicht verwendet.

Die Vision kann diese Typen später zu echten Signaturen machen:

- Ember/Volcanic: Energie oder Treibstoff
- Ocean/Ice: Biomasse oder Kühlmittel
- Violet/Golden: seltene/exotische Materie
- Toxic: hochwertiges Material mit Risiko
- Storm/Paper/Desert: volatile Nebenressourcen

Bis diese Zuordnung in der Laufzeitproduktion konsumiert wird, bleibt sie Designabsicht und darf nicht als bestehende Spielregel dokumentiert werden.

### Planetare Spezialisierung

Der aktuelle Upgrade-Katalog enthält 13 Definitionen in vier Branches: Economy, Military, Tech und Infrastructure. Parent- und Exklusivitätsregeln, Kosten, Traits und sichtbare Upgrade-Strukturen sind implementiert.

Die geplante Richtung ist:

- Economy: Extraktor, Raffinerie oder Handel
- Military/Industry: Werft, Kriegswerft oder Kolonie-Werft
- Tech: Technologiezentrum, Waffenlabor oder Rüstungslabor
- Infrastructure: Orbitalstation und spätere Reichweiten-/Garnisonsfunktionen

Noch offen in der Implementierung sind echte Verbraucher für Ressourcenveredelung, Perimeter-Slots, Reichweite, Türme und Transformer-Freischaltungen. Die entsprechenden Trait-Felder existieren teilweise bereits, sind aber keine fertigen Systeme.

### Objekt, Transformer und Traits

Das gewünschte gemeinsame Baukastenprinzip lautet:

- **Objekt:** wiederverwendbare Grundform, etwa Planetstruktur, Schiffsrumpf oder Mech-Komponente
- **Transformer:** verändert Darstellung und verfügbare Funktionsrichtung
- **Trait/Effect:** beschreibt Werte, Boni, Kosten und gekoppelte Nachteile unabhängig vom Asset

Der aktuelle Code hat dafür nur Teilstücke:

- `TraitDefinition` wird von Planet-Upgrades verwendet.
- `TransformerConfig` behandelt aktuell hauptsächlich Faction-Tints, Orbitmathematik und Präsentationswerte.
- `PlanetDetails` erzeugt sichtbare Upgrade-Strukturen aus vorhandenen Assets.
- `ShipPartDefinition` und `ShipPartCatalog` bilden einen separaten, einfachen Ship-Builder mit Hull-, Scanner- und Modul-Slots.
- Ein allgemeiner Objekt×Transformer-Child-Pool für Planeten, Schiffe und Mechs existiert noch nicht.

Eine zukünftige Abstraktion sollte deshalb ein gemeinsames typisiertes Effect-Modell teilen, aber Planet-, Ship- und Mech-Definitions nicht künstlich zu einer einzigen Resource-Klasse verschmelzen.

## Layer 2 — Simulierte Flottenbegegnung

Layer 2 soll eine kurze, voll animierte Raumschlacht zwischen gebauten Flotten zeigen. Sie ist keine neue freie Echtzeit-Strategieschicht, sondern eine begrenzte Simulation mit visueller Rückmeldung.

Geplanter Datenfluss:

```text
FleetSnapshot A + FleetSnapshot B + BattleContext + Seed
→ deterministische Simulation
→ BattleResult + BattleEvent[]
→ Cutscene-Replay
→ atomarer Rückfluss an GameState
```

Die Schiffe sollen dabei durch eine begrenzte taktische KI gesteuert werden: Zielwahl, Formation, Fokusfeuer, Rückzug und Nutzung ihrer Loadout-Traits. Visuals dürfen die Simulation nicht heimlich durch freie Physik oder eigene Ergebnisse überschreiben.

Das Earlygame soll bewusst langsam sein. Produktionsraten, Baukosten, CPU-Entscheidungsintervalle und spätere Skalierung gehören in Resources und Kurven, nicht in Sonderfälle der Simulation.

## Layer 3 — Planetare Eroberung

Layer 3 ist die eigentliche Planetenentscheidung. Ein Angriff soll den wirtschaftlichen Wert von Verteidigung und Flottenbau sichtbar machen.

### Angreifer

Gebaute Schiffs-Loadouts werden über einen Adapter in Angreifer-Minions überführt:

```text
ShipLoadout → AssaultMinionDefinition
```

Rumpf, Antrieb, Waffen und Transformer bleiben erkennbar und liefern sowohl logische Werte als auch visuelle Identität. Die Bodenregeln dürfen die Ship-Definitions nicht kopieren; sie müssen deren Werte domänenspezifisch abbilden.

### Verteidiger

Der angegriffene Planet soll seine vorbereitete Layer-1-Infrastruktur nutzen:

- Garnison aus den vorhandenen Worker-/Cluster-Werten
- Verteidigungsanlage als Quelle für Türme oder Abwehrpunkte
- Technologiezentrum als Quelle für defensive/offensive Freischaltungen
- Orbitalstation als Quelle für Kapazität, Reichweite oder zusätzliche Verteidigungsoptionen

Die Zielrichtung ist asymmetrisch: Eigene angegriffene Planeten können aktiv verteidigt werden; eigene Angriffe können gegen deterministische gegnerische Verteidigung automatisch aufgelöst und als Spektakel gezeigt werden. Diese Szenen und Regeln existieren derzeit noch nicht.

## Stil und Präsentation

Der Paperclip-/Papercraft-Comicgedanke bleibt eine visuelle Leitlinie: klare Silhouetten, Zellschattierung, begrenzte Farbsignaturen, lesbare Routen und kleine Bewegungen. Die vorhandenen SVGs werden bevorzugt als wiederverwendbare Objekte eingesetzt; Variationen sollen langfristig durch Child-Komposition und Transformer entstehen, nicht durch eine unkontrollierte Zahl fertig gebackener Kombinationsassets.

4K bleibt eine Präsentations- und Qualitätsstufe. Die aktuelle 960×540-Viewport-Basis wird nicht als Beleg für eine bereits fertige 4K-Produktion verstanden.

## Reihenfolge

1. Layer 1 mit echten Ressourcen-, Upgrade- und Verteidigungsverbrauchern stabilisieren.
2. Ship-Builder-Assemblies zu autoritativen Loadout-Snapshots erweitern.
3. Deterministische Layer-2-Simulation und Replay-Ereignisse bauen.
4. Ship-to-Minion-Adapter und Layer-3-Verteidigung prototypen.
5. Erst danach komplexere Asset-Transformer, zusätzliche Schiffsklassen und Mech-Varianten verallgemeinern.

---

<div align="center">

| | |
|:---:|:---|
| 📡 **Lagezentrum** | [`README.md`](README.md) — Overworld-Übersicht & Preflight |
| 🪐 **Galaktisches Archiv** | [`LORE.md`](LORE.md) — Feldberichte & Planetendossiers |
| 📐 **Technischer Vertrag** | [`DESIGN.md`](DESIGN.md) — Verbindliche Spezifikation |
| 🤖 **Agenten-Leitfaden** | [`AGENTS.md`](AGENTS.md) — Ground Truth & Entwicklerregeln |
| 🗺️ **Dokumentations-Index** | [`docs/README.md`](docs/README.md) — Struktur & Zugehörigkeiten |

</div>
