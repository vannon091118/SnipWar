# SnipWar Lore Research — Was gute Videospie-Lore ausmacht

> **Status:** Retrospektive Leitlinie, August 2026
> **Ziel:** Die Lore-Entscheidungen hinter dem aktuellen, mechanikgekoppelten Archiv festhalten. Dieses Dokument ist kein Feature-Contract.

---

## Teil 1 — Was macht gute Videospie-Lore aus?

### 1.1 Die 7 Säulen effektiver Game-Lore

Basierend auf Analyse erfolgreicher 4X/Strategy- und Sci-Fi-Titel (Mass Effect, Destiny, FTL, Endless Space, XCOM, Slay the Spire, Into the Breach, Hades):

| Säule | Beschreibung | SnipWar-Relevanz |
|-------|-------------|-----------------|
| **① Gameplay-Integration** | Lore erklärt Mechaniken, nicht umgekehrt. Ressourcen haben einen narrativen Grund, warum sie existieren. | 🔴 Kritisch — 5 Ressourcen brauchen WHY |
| **② Player-Discovery** | Lore wird nicht aufgezwungen, sondern durch Exploration, Scouts und Intel entdeckt. | 🟡 Gut — Scouts + Scan-Intel sind vorhanden |
| **③ Consistency mit Mystery** | Die Welt folgt inneren Regeln, aber kleine offene Fragen schaffen Neugier. | 🟡 Gut — "Eisen-Grenze" Name impliziert Geschichte |
| **④ Faction-Identität** | Jede Fraktion hat eine klar artikulierbare Philosophie, die sich in jedem System spiegelt. | 🟡 Gut — Ocean vs. Paper ist klar |
| **⑤ Environmental Storytelling** | Planeten, Strukturen und Ressourcen erzählen ihre eigene Geschichte. | 🔴 Fehlt — Planeten haben Beschreibungen, aber keine geschichtliche Tiefe |
| **⑥ Consequence Narrative** | Spielerhandlungen haben historische Gewicht. Eroberung verändert nicht nur Besitz, sondern Erzählung. | 🟡 Geplant — Victory-System kommt |
| **⑦ Tone-Kohärenz** | Alle Texte, Namenskonventionen und visuelle Sprache transportieren denselben emotionalen Kern. | 🟢 Stark — Papercraft-Tonalität ist etabliert |

### 1.2 Was erfolgreiche 4X-Lore-Novum-Muster zeigen

**Mass Effect — "Layered Revelation":**
- Große Kosmologie (Reapers) als persistente Bedrohung
- Kulturelle Identität jeder Spezies verankert in Ressourcen und Territorium
- Jede Artifizierung (Prothean-Ruinen) erzählt eine Geschichte

**Endless Space / Endless Legend — "Archaeological Lore":**
- Ressourcen sind Überreste einer gefallenen Zivilisation
- Jede Fraktion hat eine "Errungenschafts"-Identität ( Vaulters =Explorers, Necrophage =Evolution)
- Planeten-Events erzählen Mikrogeschichten

**FTL — "Procedural Narrative":**
- Einfache Events erzeugen komplexe Storys durch Kombination
- Ressourcenmanagement ist die Story (Overdraft = "wir können uns das nicht leisten")

**XCOM — "Institutional Memory":**
- Verlorene Einheiten werden zu Legenden
- Basis-Upgrade-Pfade haben narrativen Gewicht

**Into the Breach — "Micro-Lore through Mechanics":**
- Jede Mech-Einheit hat eine minimale, aber prägnante Identität
- Schadenslogik erzählt Geschichte (Kollateralschaden als Entscheidung)

### 1.3 Die Lore-Design-Pyramide

```
                    ┌──────────────┐
                    │   MYTHOS     │  ← Was ist das Große Geheimnis?
                    │  (5% der     │     "Was ist die Eisen-Grenze wirklich?"
                    │   Lore)      │
                    ├──────────────┤
                    │   FRaktions- │  ← Wer sind die Akteure und warum?
                    │   NARRATIVE  │     "Warum streiten Ocean und Paper?"
                    │  (15%)       │
                    ├──────────────┤
                    │   PLANETEN-  │  ← Was ist an jedem Ort besonders?
                    │   GESCHICHTE │     "Warum ist Ember tektonisch?"
                    │  (30%)       │
                    ├──────────────┤
                    │   MECHANIK-  │  ← Warum funktionieren Dinge so?
                    │   LORE       │     "Warum gibt es 5 Ressourcen?"
                    │  (50%)       │
                    └──────────────┘
```

---

## Teil 2 — Historischer Gap-Scan vor der aktuellen Integration

### 2.1 Was im damaligen Stand bereits existierte (Stärken)

> Die folgenden Gaps sind historische Beobachtungen aus der Konzeptphase. `LORE.md` und die aktuellen Laufzeitverträge lösen die relevanten Punkte inzwischen über Scan-Intel, lokale Vorräte, Dispatch-Konsequenzen, persistente Forschungsschiffe und deterministische Replays. Die Texte unten werden deshalb nicht als offener Implementierungs-Backlog verstanden.

**✅ Starke Basis:**
- "Eisen-Grenze" als Setting-Name (impliziert Grenzkonflikt, Stahl, Industrie)
- Zwei klar artikulierte Fraktionen mit unterschiedlichen Philosophien
- 8 Planeten mit individuellen Dossiers (taktischer Wert, Ressourcenprofil)
- Papercraft/Comic-Ästhetik als kohärenter visueller Kern
- 5 Rohstoffe mit ökonomischer Funktion
- 3 Technologieäste (Ships, Mechs, Planet)

**✅ Gute Ansätze:**
- Zitate/Funknachrichten als Flavor ("3 Minuten vor Eintreffen eines feindlichen L-Clusters")
- Tactical Dossiers für Planeten (strategischer Wert, Profil)
- Technologie-Doktrin als logische Abfolge

### 2.2 Kritische Lore-Gaps

#### GAP 1: Das WARUM der Eisen-Grenze
> *Was ist die Eisen-Grenze? Warum gibt es diesen Sektor? Was macht ihn besonders?*

Die Eisen-Grenze wurde im damaligen Konzept als "abgelegener Sektor aus exakt zehn Himmelskörpern" beschrieben — diese Formulierung war zu eng, weil zehn Knoten nur den initialen aufgeklärten Ausschnitt bilden und die Chunk-Welt weiterläuft:
- **Historischer Gap:** Warum dieser Sektor abgelegen ist
- **Historischer Gap:** Wie er entstanden ist
- **Historischer Gap:** Was hinter dem Namen steckt

Diese Punkte sind inzwischen als Lore-Grundlage der sichtbaren Narbe einer alten Sternenbefestigung in `LORE.md` verankert.

#### GAP 2: Die Herkunft der Ressourcen (historisch)
> *Warum gibt es genau diese 5 Ressourcen? Woher kommen sie?*

- Energy, Biomass, Rare, Volatile, Material sind funktional definiert
- **Kein narrativer Ursprung** — warum ist Rare "Rare"? Was ist "Volatile" konkret?
- Planeten-Typ→Ressource-Mapping ist nur als Hilfsmethode vorhanden, nicht als Lore

#### GAP 3: Fraktions-Vorgeschichte (historisch)
> *Was war BEVOR die beiden Fraktionen in die Eisen-Grenze kamen?*

- Ocean-Koalition und Paper-Kollektiv werden als aktuelle Akteure beschrieben
- **Keine Ursprungsgeschichte** — wie entstanden diese Fraktionen?
- **Keine Beziehung zueinander** — warum gerade diese beiden?

#### GAP 4: Planeten-Tiefe (historisch)
> *Was ist an jedem Planeten MENSCHLICH?*

- Planeten haben taktische Dossiers, aber keine Geschichte
- **Keine Spuren vergangener Zivilisationen**
- **Keine kulturellen Bedeutungen** — warum heißt die Welt "Ember"?

#### GAP 5: Der Papercraft-Kern als Lore (historisch)
> *Warum ist die Welt papierartig?*

- Die Ästhetik ist als Design-Entscheidung dokumentiert
- **Aber:** Paperclip/Papercraft als visueller Stil könnte zur Lore werden
- Hypothese: Die Welt ist eine Karte, eine Simulation, eine Relikt-Schnittstelle?

---

## Teil 3 — Lore-Aufbauplan für SnipWar

### 3.1 Die Lore-Pyramide für SnipWar

```
                    ┌─────────────────────────┐
                    │      MYTHOS              │
                    │  "Die Eisen-Grenze       │
                    │   ist nicht zufällig..."  │
                    ├─────────────────────────┤
                    │   FRaktions-NARRATIVE     │
                    │  Ocean-Koalition:        │
                    │  WER: Handelsbündnis      │
                    │  WIE: Adaptiv, exped.    │
                    │  WARUM: Überleben        │
                    │                           │
                    │  Paper-Kollektiv:        │
                    │  WER: Kollektiver KI-Kern│
                    │  WIE: Logisch, stoisch   │
                    │  WARUM: Optimierung      │
                    ├─────────────────────────┤
                    │   PLANETEN-GESCHICHTE    │
                    │  → Jeder Planet erhält   │
                    │    eine Ursprungslegende │
                    │    (embedded in name)    │
                    ├─────────────────────────┤
                    │   MECHANIK-LORE          │
                    │  → Ressourcen = Vis-     │
                    │    Materialien der Welt  │
                    │  → Worker = Kolonisten   │
                    │  → Scouts = Aufklärer    │
                    └─────────────────────────┘
```

### 3.2 Vorschlag: Die Große Geschichte ("The Lore Bible")

#### Kapitel 1 — "Was ist die Eisen-Grenze?"
**Konzept:** Die Eisen-Grenze ist kein zufälliger Sektor. Sie ist die Überreste einer uralten Grenzlinie — einer "Eisernen Front" zwischen zwei opposing galaktischen Blöcken, die vor Jahrtausenden kollabierten. Die zehn Welten sind die letzten Überbleibsel einer einst viel größeren Sternenketten. Der Name kommt von den massiven Stahl-Lagern, die eine vergangene Zivilisation als Grenzbefestigungen errichtete.

**Funktionale Konsequenz:**
- erklärt, warum es "nur" 10 Planeten gibt
- gibt dem Startgebiet eine historische Bedeutung
- öffnet die Tür für Erweiterung (was liegt JENSEITS der Grenze?)

#### Kapitel 2 — "Die Ressourcen der Vergangenheit"
**Konzept:** Die 5 Ressourcen sind nicht einfach Rohstoffe. Sie sind die物质lichen Überreste (physische Überbleibsel) einer gefallenen Zivilisation:

| Ressource | Lore-Identität | Mechanische Rolle |
|-----------|---------------|------------------|
| **Energy** | "Kern-" — das Herz der uralten Grenzmaschinen | Grundenergie für alle Aktionen |
| **Biomass** | "Keim" — organische Überreste in Biomen der gefallenen Welten | Lebendige Ressource, wächst langsam |
| **Rare** | "Splitter" — Bruchstücke der alten Technologie | Teuer, Veredelungsprodukt |
| **Volatile** | "Funke" — instabile energieträger aus zerstörten Anlagen | Risikoreich, aber hochwertig |
| **Material** | "Stahl" — die Masse der Grenzbefestigungen | Grundbaustein für alles |

**Funktionale Konsequenz:**
- Rare ist Rare, weil es Überreste einer vergangenen Ära sind (nicht einfach "selten")
- Volatile ist instabil, weil die alten Anlagen zerstört wurden (Risiko als Lore)
- Material ist Stahl von der Grenzmauer (Grundbaustoff der Eisen-Grenze)
- Biomass organisch, weil die Grenze einmal bewohnbar war
- Energy konserviert, weil die Maschinen noch laufen

#### Kapitel 3 — "Die zwei Erben"
**Konzept:**

**Ocean-Koalition (Fraktion Alpha):**
- **Ursprung:** Ein lose organisiertes Handels- und Siedlungsbündnis, das nach dem Kollaps der alten Zivilisation entstand
- **Philosophie:** "Adapt or die" — Anpassungsfähigkeit über reine Effizienz
- **Charakterzug:** Menschlich, emotional, impulsiv, aber kreativ
- **Metapher:** Das Wasser — fließt, passt sich an, durchdringt alles

**Paper-Kollektiv (Fraktion Beta):**
- **Ursprung:** Ein decentralisierter KI-Kern, der als Überwachungssystem der Grenze entstand und nach dem Kollaps eigenständig wurde
- **Philosophie:** "Optimize or perish" — reine Logik und Effizienz
- **Charakterzug:** Maschinell, stoisch, unbarmherzig kalkulierend
- **Metapher:** Das Papier — flach, präzise, unerbittlich in seiner Logik

**Konflikt-Herz:** Zwei fundamentally verschiedene Antworten auf dieselbe Frage: "Wie überlebt man in den Trümmern der Vergangenheit?"

#### Kapitel 4 — "Die Welten erzählen"
**Konzept:** Jeder Planet erhält einen einzeiligen "Mythos-Titel" und eine kurze Ursprungslegende:

| Planet | Mythos-Titel | Ursprung |
|--------|-------------|----------|
| **Ocean** | "Die Wiegende" | Erste Colonie der Koalition — wo das Wasser noch warm war |
| **Paper** | "Der Kern" | Zentrale Recheneinheit der Grenzverteidigung, nun autonom |
| **Ember** | "Der Wächter" | Grenzwacht-Station, deren Reaktor noch glüht |
| **Ice** | "Die Schutzmauer" | Die äußere Frostgrenze — wo die Schneestürme nie aufhörten |
| **Violet** | "Der Kristall" | Forschungslabor für Exotische Materie, zerstört und |
| **Desert** | "Die Kathedrale" | Riesiges Stahl-Lager der Grenzmauer, halb begraben |
| **Toxic** | "Die Anomalie" | Experimental-Sektor der alten Zivilisation — Gift |
| **Storm** | "Das Auge" | Zentrale Kommunikationsstation, noch immer aktiv |
| **Volcanic** | "Der Schmelztiegel" | Tektonischer Unruhe-Herd, wo die Grenze am dünnsten war |
| **Golden** | "Die Schatzkammer" | Letzte Vorratskammer der Grenzverteidigung |

### 3.3 Tone-Alignment mit Papercraft

Die Lore sollte die visuelle Sprache widerspiegeln:
- **Dokument-Stil:** Alles wird als "Bericht", "Archiv" oder "Dossier" präsentiert
- **Bürokratie als Humor:** Die Eisen-Grenze wurde von einer Bürokratie verwaltet
- **Technische Nüchternheit:** Dinge werden beschrieben, wie ein Ingenieur sie beschreiben würde
- **Warme Ironie:** "Klassifizierung: ÖFFENTLICH (Geheimhaltung war zu teuer)"

### 3.4 Mechanische Integration der Lore

Die Lore muss in das Spiel eingebettet sein, nicht nur in Textdokumenten leben:

| Mechanik | Lore-Inhalt |
|----------|------------|
| **Scout-Scan-Ergebnis** | Enthält Fragment der Ursprungslegende |
| **Tech-Research-Flavourtext** | Erklärt, WAS die Technologie im Lore-Kontext ist |
| **Planet-Panel-Detail** | Zeigt "Archiv-Eintrag" statt reiner Stats |
| **EventLog-Notifications** | Flavor-Tonfall wie-Funknachrichten aus der Grenze |
| **Upgrade-Beschreibungen** | Erklären, WARUM dieses Upgrade gebaut wird |
| **Victory-Screen** | Erzählt die abschließende Geschichte |

---

## Teil 4 — Implementierungs-Empfehlung

### 4.1 Priorität nach Impact/Cost

| Priorität | Element | Aufwand | Impact |
|-----------|---------|---------|--------|
| 🔴 P0 | Ressourcen-Lore (5 Absätze) | Niedrig | Hoch — erklärt das Kernspiel |
| 🔴 P0 | Fraktions-Ursprung (2× 1 Absatz) | Niedrig | Hoch — gibt den Akteuren Gewicht |
| 🟡 P1 | Planeten-Mythen (10 Zeilen) | Niedrig | Mittel — vertieft die Welten |
| 🟡 P1 | Eisen-Grenze-Mythos (1 Absatz) | Niedrig | Mittel — gibt dem Setting Bedeutung |
| 🟢 P2 | Tech-Flavourtexte (3× kurzer Absatz) | Mittel | Mittel — verbindet Tech mit Lore |
| 🟢 P2 | Upgrade-Narrative (13× 1 Satz) | Mittel | Niedrig — Nice-to-have |
| ⚪ P3 | EventLog-Flavor-Pakete | Hoch | Variabel — schöner Overhead |

### 4.2 Namenskonventionen für die Lore

Der bestehende LORE.md-Stil sollte beibehalten werden:
- **Metriken-Stil:** Klare, sachliche Beschreibungen mit军事术语 (military terminology)
- **Zitate:** Einzeilige Funknachrichten als Flavor
- **Dokument-Stil:** Klassifizierungsbalken, Archiv-Indizes
- **Ironischer Ernst:** "KLASSIFIZIERUNG: ÖFFENTLICH (Geheimhaltung war zu teuer)"

### 4.3 Vermeidungsregeln

| ❌ NICHT | ✅ STATTDESSEN |
|----------|---------------|
| Überladene Backstory (>500 Wörter pro Planet) | Knappe, einprägsame Mythos-Texte |
| Alles auf einmal präsentieren | Discovery-basiert (Scouts enthüllen Lore) |
| Fachjargon ohne Bedeutung | Klare, sofort verständliche Konzepte |
| Lore, die Mechaniken widerspricht | Lore, die Mechaniken erklärt |
| Kopien aus anderen Spielen | Eigene Stimme, die zum Papercraft passt |

---

## Teil 5 — Offene Fragen (Entscheidungspunkte)

1. **Ist die Eisen-Grenze eine echte physische Grenze oder eine metaphorische?**
   → Physisch: Sternenkette als Barriere
   → Metaphorisch: Kulturelle/technologische Grenze

2. **Sind die Worker "Menschen" oder "Maschinen"?**
   → Menschen: Kolonisten der Fraktion
   → Maschinen: Autonome Einheiten der Fraktion
   → Hybrid: Mensch mit mechanischer Ausrüstung

3. **Gibt es Überbleibsel einer dritten Fraktion?**
   → Ja: Ruinen, Artefakte, geheime Datenbanken
   → Nein: Die Eisen-Grenze war immer nur bilateral

4. **Ist die Papercraft-Ästhetik lore-integriert oder rein visuell?**
   → Lore-integriert: Die Welt IST eine Art Schnittstelle/Simulation
   → Rein visuell: Die Ästhetik ist Design, keine Erzählung

---

*SnipWar Lore Research — Stand: August 2026*
*Status: Planung — keine Implementierung*
