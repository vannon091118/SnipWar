<div align="center">

<pre>
╔══════════════════════════════════════════════════════════════╗
║  S N I P W A R  //  I R O N   F R O N T I E R              ║
║  ──────────────────────────────────────────────────────────  ║
║  TEN WORLDS · ONE FLEET · NO SAFE ORBIT                    ║
╚══════════════════════════════════════════════════════════════╝
</pre>

# SNIPWAR
### Eine taktische Mech-Saga zwischen den Sternen

[![Engine: Godot 4.7](https://img.shields.io/badge/Engine-Godot%204.7-478cbf?style=for-the-badge&logo=godotengine&logoColor=white)](https://godotengine.org/)
[![Status: Prototype](https://img.shields.io/badge/Status-Prototype-f0b429?style=for-the-badge)](#status)
[![Target: 4K](https://img.shields.io/badge/Presentation%20Target-4K-ef476f?style=for-the-badge)](#vision)

> **Die Galaxie ist kein Schlachtfeld. Sie ist die Waffe.**

</div>

<a id="vision"></a>

## ░ TRANSMISSION / 01 — DIE VISION

SnipWar ist ein taktisches Mech-Wargame mit einer klaren Silhouette und einem großen Horizont: farbige Welten, wandernde Einheiten und Entscheidungen, die sich wie Funkfeuer durch ein Sternensystem ausbreiten.

Die geplante Endfassung denkt in 4K — nicht als bloße Auflösung, sondern als Raum für Details: leuchtende Routen, lesbare Kampfzonen, markante Mech-Profile und eine Galaxiekarte, die auch auf Distanz verständlich bleibt. Der aktuelle Build ist der spielbare Kern dieser Reise, noch klein genug zum Umbauen und bereits lebendig genug zum Erkunden.

## ░ DAS THEATER

Zehn Planeten bilden ein unruhiges Netz aus Ressourcen, Heimatwelten und Gefahren. Ihre Positionen werden deterministisch verteilt, damit ein Seed reproduzierbare taktische Räume erzeugt, während der Laufstart später für neue Karten sorgen kann.

- Der deterministische Generator verteilt zwei XL-Welten und einen L-Sektor als große Fixpunkte.
- Die Größenverteilung hängt am Seed; dadurch ändern sich Position und Spawn-Rhythmus gemeinsam, ohne die Rollen der Planeten zu verlieren.
- **Toxic**, **Volcanic** und **Storm** markieren Zonen, in denen die Karte nicht neutral bleibt.
- Meteore ziehen durch den Vordergrund; PlanetDetails ergänzt seed-basiert bis zu drei Extras, bei Toxic garantiert einen Satelliten und mehrere Asteroiden in der Umlaufbahn sowie optional einen Kometen.
- Ein Netzwerk aus Nachbarfeldern macht erreichbare Ziele sichtbar, statt sie in Menüs zu verstecken.

## ░ DIE KRIEGSMASCHINE

Die Mechs kommen nicht aus einem Auswahlbildschirm. Sie werden über die Planetenlogistik in Stellung gebracht.

1. Einen Planeten anwählen.
2. Die Einheitenzahl und das gewünschte Ziel prüfen.
3. Eine Route im persistenten Planeten-Tab setzen.
4. Verstärkung anfordern und den nächsten taktischen Schritt vorbereiten.

Die aktuelle Spawn-Logik unterscheidet die Welten bereits nach Größe: XL-Planeten liefern drei Einheiten im Fünf-Sekunden-Takt, L-Planeten zwei im Sieben-Sekunden-Takt, variable Welten eine im Zehn-Sekunden-Takt. Bewegung, Kampf und die vollständige Mech-Kommandoschicht gehören zur nächsten Ausbaustufe — der Prototyp hält die Einheiten bewusst zunächst als sichtbare, registrierte Präsenz auf ihrer Welt.

## ░ VISUELLE DIREKTIVE

**Hard sci-fi framing. Arcade readability. Hand-made signal noise.**

SnipWar setzt auf kontrastreiche Farben, reduzierte Formen und kleine Bewegungen, die der Karte Leben geben, ohne die taktische Lesbarkeit zu opfern. Der Look darf spielerisch sein; die Entscheidungen darunter sollen es nicht sein. Jede Welt soll auf einen Blick eine Stimmung, eine Funktion und eine mögliche Bedrohung vermitteln.

<a id="status"></a>

## ░ STATUS // BUILD 0.1

**Heute spielbar:**

- deterministische Galaxiekarte mit zehn Planeten
- unterschiedliche Weltgrößen und Rollen
- zwei Fraktionszuordnungen auf der Karte
- automatische Cluster-Spawns mit Live-Zähler
- auswählbare Ziele und benachbarte Routen
- animierte Meteore und seed-basierte Planetendetails
- Headless-Preflight für die wichtigsten Systemschnittstellen

**Noch im Hangar:**

- Mech-Sprites, Loadouts und individuelle Fähigkeiten
- echte Route-Bewegung und Ankunftslogik
- Ressourcen, Schaden, Eroberung und Siegbedingungen
- Gefechtsansicht zwischen den Planeten
- 4K-optimierte Präsentation und Kamera

## ░ STARTUP SEQUENCE

Voraussetzungen:

- [Godot 4.7](https://godotengine.org/download/archive/4.7.2-stable/)
- Windows oder eine kompatible Umgebung für den aktuellen Projektstand

Projekt starten:

```text
Godot öffnen → Projekt importieren → project.godot → F6/F5
```

Der aktuelle Entwurf nutzt eine 960×540-Viewport-Basis, die später auf eine hochauflösende Präsentation skaliert werden kann. Für einen automatisierten Smoke-Test auf Windows:

```text
C:/Users/Vannon/Desktop/godu/Godot_v4.7.2-stable_win64_console.exe --headless --path . --quit-after 2
```

## ░ ROADMAP / NÄCHSTE SPRÜNGE

- **01 — Command layer:** Mech-Klassen, Auswahl und Befehle.
- **02 — Transit layer:** Routen mit sichtbarer Bewegung und Ankunft.
- **03 — Conflict layer:** Planetare Gefechte mit Ressourcenrisiko.
- **04 — Campaign layer:** Fraktionen, Szenarien und verzweigte Ziele.
- **05 — 4K layer:** hochauflösende UI-, VFX- und Kamera-Passagen.

## ░ CALLSIGN

SnipWar ist kein fertiges Universum, sondern seine erste Funkmeldung. Der Planetenkern steht; jetzt wird aus Raumordnung Kriegskunst.

<div align="center">

**`CONNECT · DEPLOY · HOLD THE LINE`**

</div>
