# SnipWar — Vision

Dieses Dokument beschreibt eine mögliche Richtung für SnipWar. Es ist kein Feature-Vertrag und keine abschließende technische Spezifikation. Begriffe wie „könnte“, „denkbar“ und „perspektivisch“ lassen Raum für Balancing, Prototyping und spätere Kurskorrekturen.

## Ausgangslage

Der aktuelle Vertical Slice bildet bereits eine strategische Overworld-Grundlage:

- zehn Planeten mit SVG-Assets und seed-basierter Verteilung
- Größenklassen, die Positionierung und Einheitenproduktion beeinflussen
- logische Planetenzähler statt dauerhaft sichtbarer Einheiten
- Zielauswahl, Flugzeitvorschau und sichtbarer Transit
- K/M/L-Cluster in einer geordneten Formation
- seed-basierte Planetendetails mit einer kleinen Zahl an Extras

Damit ist ein schrittweiser Ausbau technisch plausibel. Die späteren Wirtschafts-, Upgrade- und Gefechtssysteme sind jedoch noch keine Bestandteile des aktuellen MVP.

## Ein möglicher Spielkreislauf

Unterschiedliche Planeteneigenschaften könnten unterschiedliche Ressourcenströme erzeugen. Daraus könnte Expansionsdruck entstehen: Neue Welten, Handelswege oder Konflikte würden die wirtschaftliche Ausgangslage verändern. Begegnungen zwischen Flotten könnten in eine kurze Übergangsdarstellung und anschließend in eine Gefechtssituation führen. Deren Ergebnis könnte Besitz, Garnison und Ressourcenfluss wieder auf der Galaxiekarte beeinflussen.

Dieser Kreislauf beschreibt die gewünschte Verbindung der Ebenen, ohne eine bestimmte Reihenfolge, Balance oder Kampfregel vorwegzunehmen.

## Layer 1 — Strategische Overworld

### Planetare Identität und Ressourcen

Die vorhandenen Planetentypen bieten eine gute Grundlage für unterschiedliche Ressourcenprofile. Als thematische Richtung wären beispielsweise folgende Zuordnungen denkbar:

- Ember und Volcanic: Energie oder Treibstoff
- Ocean und Ice: Biomasse oder Kühlung
- Violet und Golden: seltene oder exotische Materialien
- Toxic: wertvolle Materialien mit einem möglichen Risiko
- Storm, Paper und Desert: wechselhafte Nebenressourcen

Diese Gruppen sind Gestaltungshypothesen, keine festgelegten Ertrags- oder Balancingwerte. Die vorhandenen `planet_role`- und Fraktionsdaten könnten später um echte Ressourcen-, Besitz- und Produktionsdaten ergänzt werden.

### Aufbau und Spezialisierung

Ein Planet könnte sich über mehrere Richtungen entwickeln, ohne dass dafür ein einfacher Levelzähler nötig wäre. Als mögliche Bereiche bieten sich an:

- Wirtschaft: Extraktion, Verarbeitung oder Handel
- Militär und Industrie: Werften, schwerere Verbände oder Verteidigung
- Technologie: Waffen- und Rüstungsforschung
- Infrastruktur: Orbitalstationen, Reichweite oder Kapazität

Ob Zweige einander ausschließen, kombinierbar sind oder sich über Kosten begrenzen, kann sich aus dem späteren Spielgefühl ergeben. Sichtbare Gebäude oder Orbitobjekte könnten den Ausbau lesbar machen und zugleich das bestehende Asset-Baukastenprinzip erweitern.

### Flottenrollen und Besitz

Die bestehende Dispatch-Logik könnte perspektivisch neben Kampfverbänden auch Frachter oder Kolonieschiffe tragen. Frachter würden eher Ressourcen bewegen, Kolonieschiffe könnten unbesetzte Welten erschließen, und Kampfcluster würden die bisherige Transitdarstellung weiterführen.

Dafür würde sich ein eigener Spielzustand für Besitz, neutrale Ziele und unterschiedliche Transportgüter anbieten. Die heutigen Fraktions- und Rollenmarkierungen sind dafür ein Anschluss, aber noch keine Besitz- oder Eroberungsmechanik.

## Objekt-, Transformator- und Trait-Idee

Ein gemeinsamer Baukasten könnte spätere Planeten- und Mech-Varianten überschaubar halten:

- Ein **Objekt** beschreibt die wiederverwendbare Grundform, etwa einen Rumpf, eine Werft oder eine Waffenhalterung.
- Ein **Transformator** könnte Aussehen oder Funktionsrichtung verändern, etwa Farbe, Projektiltyp oder Antrieb.
- Eine **Trait-Tabelle** könnte die Auswirkungen einer Kombination beschreiben, einschließlich möglicher Vorteile und Nachteile.

Das vorhandene `Attachments`-Node der Transit-Cluster ist lediglich ein visueller Erweiterungspunkt. Es bildet diesen Baukasten noch nicht ab. Eine konkrete erste Kombination wäre wahrscheinlich aussagekräftiger als eine allgemeine Abstraktion, bevor sich die tatsächlichen Varianten wiederholen.

## Layer 2 — Übergang zwischen Karte und Gefecht

Bei einem Flottenkontakt könnte eine kurze, automatisch ablaufende Szene die Umgebung des Treffpunkts zeigen. Die Planetenpositionen, SVG-Assets und Hintergrundelemente der Overworld könnten dabei als Grundlage für eine räumliche Inszenierung dienen.

Die Szene könnte Stärkeverhältnisse oder erwartete Verluste andeuten und anschließend an das Gefecht übergeben. Eine eigene Entscheidungsebene wäre dafür nicht zwingend nötig; ihr Umfang könnte bewusst klein bleiben, solange die strategische Karte im Vordergrund steht.

## Layer 3 — Gefecht und Rückkopplung

Eine mögliche asymmetrische Rollenverteilung wäre:

- Bei einem Angriff auf den eigenen Planeten übernimmt der Spieler eher die aktive Verteidigung, beispielsweise in einer Tower-Defense-artigen Ansicht.
- Bei einem eigenen Angriff könnte die gegnerische Verteidigung aus Besitz, Ausbau und Garnisonswerten automatisch aufgelöst werden.

Das wäre eine mögliche Dramaturgie, keine festgelegte Kampfregel. Für eine Umsetzung könnten zunächst Kampfwerte, Verluste, Besitzwechsel und ein Übergangszustand zwischen Transit und Gefecht als eigene Prototypen erprobt werden.

Die Overworld könnte weiterhin nur logische Zähler anzeigen. Eine spätere Gefechtsszene könnte daraus vorübergehend sichtbare Verteidiger erzeugen, ohne die aktuelle Regel für ruhende Einheiten auf der Galaxiekarte aufzugeben.

## Stil und Präsentation

Der Paperclip-/Papercraft-Comicgedanke lässt sich mit den vorhandenen SVG-Assets, klaren Silhouetten, Zellschattierung und begrenzten Farbsignaturen weiterführen. Der Stil darf spielerisch wirken, während Routen, Mengen und Bedrohungen lesbar bleiben.

4K eignet sich als spätere Präsentations- und Qualitätsstufe. Die aktuelle 960×540-Viewport-Basis und die skalierbaren Assets liefern dafür eine brauchbare technische Ausgangslage, ohne die nächsten Prototypen an eine sofortige 4K-Produktion zu binden.

## Technische Anschlussfähigkeit

Ein risikoarmer Ausbau könnte sich an den vorhandenen Schichten orientieren:

1. Die Overworld und den Transit als Ausgangspunkt weiterverwenden.
2. Ressourcen, Besitz und Ausbauten zunächst als klar getrennte Planetendaten erproben.
3. Einen kleinen sichtbaren Upgrade-Fall mit einem konkreten Asset testen.
4. Mit wachsender Erfahrung gemeinsame Transformatoren, Traits und zusätzliche Schiffstypen verallgemeinern.
5. Übergangsszene und Gefecht als eigene Laufzeitbereiche ergänzen, sobald ihre Zustände und Rückkopplungen klar genug wirken.

So bleibt die Vision groß genug für ein 4X-Mech-Spiel, ohne den aktuellen Vertical Slice mit noch nicht benötigten Systemen zu überladen.

## Bewusst offen

Die Vision lässt unter anderem Ressourcenwerte, Besitzregeln, Upgrade-Kombinationen, Kampfsteuerung, Umfang der Übergangsszene und die genaue Bedeutung von „Paperclip“ als Stilbegriff offen. Diese Punkte können durch Prototypen und Spieltests konkretisiert werden, statt sie vorab als unveränderliche Architektur festzuschreiben.
