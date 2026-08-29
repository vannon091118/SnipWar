# SnipWar — Vollständiger Codebasis-Audit

> ⚠️ **HISTORISCH** — Dieses Dokument wurde am 29.08.2026 erstellt und部分weise durch neuere Commits (R-050, R-051) überholt. Die aktuelle Wahrheit lebt in `ROADMAP.md`, `docs/FINDINGS.md` und `ARCHITECTURE.md`. Einzigartige Inhalte (Datenfluss, Verantwortungsgrenzen, Simulationsmodell) bleiben als historische Referenz gültig.

**Stand:** 2026-08-29 (historisch,部分weise veraltet)
**Scope:** Gesamtprojekt, mit Schwerpunkt auf deterministischer Vorgeschichte, Chronik, Playback, Weltprojektion und Übergang in Live-Gameplay.

## 1. Executive Summary

Der beschriebene Kernfluss ist im Repository bereits weitgehend implementiert:

```text
GameState → EventBus → WorldChronicle → HistorySimulator
                                      ↓
             HistoryEvent / Biografie / Chains / Eras / Beziehungen
                                      ↓
                     ChronicleSaveData → RunSaveData
                                      ↓
              HistoricalSnapshot → PlaybackController → HistoricalRenderer
```

Die Simulation ist keine Lore-Textmaschine. `HistorySimulator` erzeugt aus einem temporären `WorldState` strukturierte Fakten. `ChronicleTemplateResolver` projiziert diese Fakten anschließend sprachabhängig auf Templates. `GameState` bleibt die autoritative laufende Spielwelt; `WorldState` ist nur ein temporärer Sandkasten für die Vorgeschichte.

Der wesentliche verbleibende Produktabstand lag (bis R-050) in der fehlenden echten Vorstart-World-Scene. **Aktueller Stand:** HistoricalWorld ist implementiert, verdrahtet und durch Preflight-Gate abgesichert (R-050+R-051). Verbleibende Lücken: Year-0-Handoff (R-052), SVG-Komposition, vollständige Verbindung von Snapshot-Playback zu sichtbarem Startfluss. Die vorhandenen Presentation-Klassen sind testbar, aber noch nicht in `SceneDirector`/Main-Menu als eigenständiger Nutzerfluss registriert.

## 2. Repository-Architektur

### 2.1 Laufzeit-Schichten

| Schicht | Autoritative Komponenten | Befund |
|---|---|---|
| Einstieg | `scenes/main_menu/main_menu.tscn`, `scripts/ui/main_menu.gd` | vorhanden |
| Strategie-Welt | `scenes/world/world.tscn`, `WorldBootstrap`, `SeededLayout`, `PlanetNetwork` | vorhanden |
| Kampf | `BattleScene`, `FleetBattleSimulator` | vorhanden |
| Eroberung | `ConquestScene`, `ConquestSimulator` | vorhanden |
| Globaler Zustand | `GameState` + vier Domains | vorhanden, SSOT |
| Ereignisgrenze | `EventBus` | vorhanden |
| Chronik | `WorldChronicle`, `ChronicleSaveData` | vorhanden und persistiert |
| historische Simulation | `HistorySimulator`, `WorldState`, `FactionAI`, `HistoryEventFactory` | vorhanden, deterministisch |
| Projektion | `HistoricalSnapshot`, `PlaybackController`, `HistoricalRenderer` | vorhanden, isoliert getestet |
| Archiv-UI | `ChronicleArchiveView` | vorhanden, nicht als sichtbarer Hauptfluss verdrahtet |
| Vorstart-Welt | eigenständige `HistoricalWorld.tscn` | **FIXED** (R-050: RunPreparation + Bootstrap + Reconnect; R-051: Preflight-Gate 44/44) |
| DOKI Runtime | Python `narrative_runtime` | getrennt, nicht mit Game-History vermischen |

### 2.2 Autoloads

`project.godot` registriert unter anderem:

- `EventBus`
- `GameState`
- `WorldChronicle`
- `GameCycleManager`
- `SceneDirectorService`
- `SaveGameService`
- `EventLog`

Der EventBoundary-Vertrag ist korrekt: `WorldChronicle` hängt nicht direkt an `GameState.run_started`, sondern konsumiert `EventBus.game_event`.

## 3. Datenfluss und Verantwortungsgrenzen

### 3.1 Neue Spielsession

```text
WorldBootstrap._configure_game_state()
  → GameState.begin_new_game()
  → EventBus.emit_event("run_started", {run_id, layout_seed})
  → WorldChronicle._on_game_event()
  → WorldChronicle._on_run_started()
  → GameState.faction_planet_snapshot()
  → HistorySimulator.simulate()
  → ChronicleSaveData
```

Die Extraktion unterscheidet korrekt zwischen:

- echten Laufzeitfakten: Fraktions-IDs, Besitz, Planet-IDs
- Simulationsbaselines: Population, Wirtschaft, Militär, Forschung, Mood

Diese Baselines sind derzeit deterministische Startannahmen, nicht bereits gespeicherte Gameplaywerte. Das muss in jeder UI/Dokumentation klar bleiben.

### 3.2 Live-Gameplay

`GameState` übersetzt Domain-Signale in `EventBus`-Events. `WorldChronicle` verarbeitet aktuell insbesondere:

- `faction_changed` → `conquest`
- `technology_researched` → `research`
- `milestone_reached` → `milestone`

Damit existiert bereits ein gemeinsamer Archivpfad für Vergangenheit und Gameplay. Die Abdeckung ist jedoch nicht vollständig: Bau, Ressourcen, Handel, Transit, Schiffsstart/-verlust, Gebäudeverlust und Kampfreplays werden zwar über den Bus ausgesendet, aber noch nicht alle als strukturierte `HistoryEvent`-Typen in die Chronik projiziert.

### 3.3 Speicherung

`RunSaveData.chronicle` enthält:

- Backstory-Events
- Live-Events
- Biografien
- Chains
- Eras
- Beziehungen
- Locale
- Live-ID-Zähler

`GameState.snapshot_run()` und `restore_run()` kapseln die Chronik in den normalen Run-Save. Der Save-Roundtrip ist durch Preflight abgedeckt.

## 4. Historische Simulation

### 4.1 Modell

`WorldState` ist `RefCounted` und enthält:

- Fraktionen und Kräftewerte
- Planetenbesitz
- gerichtete Beziehungen
- Technologien
- Charaktere
- aktive Kriege
- Waffenstillstände
- Jahresstand

`HistorySimulator` führt standardmäßig 300 Jahre von `-300` bis `0` aus. Die Jahresloop verarbeitet:

1. Wirtschaft und Unterhalt
2. World Pressures
3. Charakterlebenszyklen
4. Faction-AI-Aktionen
5. Mood-Anpassung
6. optionale Snapshots

### 4.2 Aktionen und Kausalität

Die Faction-AI verwendet semantische Aktionsnamen wie `EXPEDITION`, `BUILD_INFRASTRUCTURE`, `FORM_ALLIANCE` und `DECLARE_RIVALRY`; der Simulator normalisiert sie auf sein internes Format. Dieser Adapter ist richtig, weil der existierende Simulator nicht auf ein veraltetes Vokabular zurückgebaut werden soll.

Kausalität wird über zwei Mechanismen erzeugt:

- unmittelbare `cause_event_id`-Verknüpfung im Simulator
- nachträgliches `CauseTracker.auto_link()` über Eventfenster

Kriegslebenszyklus und Totaleroberungsfälle sind bereits root-cause-korrigiert: Kriegsschlüssel verwenden Fraktionspaare, Schlachten aktualisieren die richtige Kriegshistorie, territorienlose Gegner erzwingen Frieden, und Frieden verbessert Beziehungen.

### 4.3 Resultate der lokalen Tests

Der Kernlauf produziert abhängig vom Fixture mehrere hundert Events. Verifiziert wurden unter anderem:

- 487 Backstory-Events, 61 Biografien, 56 Chains, 4 Eras
- 419 Backstory-Events, 62 Biografien, 48 Chains, 4 Eras
- deterministischer Vollhash bei gleichem Seed
- abweichender Vollhash bei anderem Seed

Die Zahlen variieren abhängig von initialen Fraktionen/Planeten; das ist erwartbar und kein Determinismusfehler.

## 5. Faktenmodell und Textprojektion

`HistoryEvent` enthält nur strukturierte Fakten:

- ID, Jahr, Typ
- Akteure und Ziel
- Gewinner/Verlierer
- Verluste und Beziehungsänderung
- Territoriumsänderung
- Wichtigkeit
- Chain- und Cause-Referenz
- Kontext

`trigger` ist aktuell als kurzer beschreibender Kontext enthalten. Er darf nicht zur autoritativen Simulation oder zu frei erfundener Lore werden. Die eigentliche Anzeige läuft über `HistoricalPerspective` und `ChronicleTemplateResolver`.

Es existieren 36 Templates pro Locale für Deutsch und Englisch. Der Simulator greift nicht auf Locale-Texte zu. Die Sprachauswahl verändert weder RNG noch Weltzustand.

## 6. Figuren und Chains

`CharacterBiography` wird aus dem Simulationszustand aufgebaut und enthält:

- Geburt/Tod
- Ranghistorie
- Ereignisverweise
- Errungenschaften
- Fehlschläge
- Beziehungen und Reputation

`ChainDetector` gruppiert Ereignisse in kausale, Kriegs-, diplomatische und Figurenketten. `ChronicleArchiveView` stellt diese Daten in drei Bereichen dar:

1. Weltchronik
2. Machtgefüge und Diplomatie
3. Persönlichkeiten

### Bekannte Präsentationsinkonsistenz

Die Archiv-UI enthält noch feste historische Testfraktionen (`solari`, `vanguard`, `krypton_miners`). Der echte Lifecycle verwendet dagegen `a`, `b` und `neutral`. Das ist ein echter Produktfehler: Filter und Relationsansicht können bei realen Runs leer oder falsch sein. Die UI muss Fraktionen dynamisch aus Snapshot/Chronicle-Daten beziehen und darf keine Testnamen hard-coden.

## 7. Snapshot, Playback und Renderer

### 7.1 Snapshot-Vertrag

`HistoricalSnapshot` ist eine reine Datenklasse und kennt nur:

- Jahr
- Ownership `planet_id → faction_id`
- Events bis zum Snapshotjahr

`simulate_with_snapshots()` verspricht, dass Snapshot-Ableitung weder RNG noch Events mutiert. Der Test bestätigt identische Eventfolgen zwischen `simulate()` und Snapshot-Modus.

### 7.2 Playback

`PlaybackController` bietet:

- `load_snapshots`
- `seek`
- `next`/`prev`
- `play`/`pause`
- `snapshot_changed`

Das ist eine korrekte Presentation-Boundary. Der Controller kennt weder Simulator noch GameState.

### 7.3 Renderer

`HistoricalRenderer` erzeugt pro Planet einen Node2D-Knoten, verwendet vorhandene Planet-SVGs und färbt nach Fraktion. Das erfüllt den Minimalvertrag „Snapshot → Visual“. Es fehlen jedoch noch:

- sichtbare Ownership-Ringe als eigenständige Bausteine
- Entwicklungsstufen für Kolonie, Industrie, Forschung und Verteidigung
- Handels-/Flottenpfade
- Kamerafokus auf Wendepunkte
- stabile, katalogbasierte Planetdaten statt eines kleinen statischen Texturarrays
- eigene Scene-Komposition mit definiertem Hintergrund und UI-Hierarchie

## 8. Verifikation

### Erfolgreich

| Prüfung | Ergebnis |
|---|---|
| Godot Editor-Scan | abgeschlossen; Port-6010-Warnung durch bereits belegten Editor-Port |
| Compile Gate | PASS, 312 gescannte Skripte |
| Chronicle Core Test | PASS, 22/22 |
| Chronicle Lifecycle Test | PASS, 21/21 |
| Historical Playback Test | PASS, 18/18 |
| Full Preflight | PASS, 43/43 Constraints, 2023/2023 Assertions |

Der vollständige Preflight lief mit Seed-/Fixture-Prüfungen in ca. 63 Sekunden. Isolation-Warnings sind dokumentierte Testmutationen und wurden nicht als verdeckte Fehler verschwiegen.

### Verifikationswarnungen

- `compile_gate` meldet normale `Cannot reload script while instances exist`-Rauschspuren, beendet aber mit PASS.
- Editor-Scan meldet Port 6010 als belegt; das verhinderte den Scan nicht.
- ConceptIndex meldet 22 ungemappte History-Klassen. Das ist kein funktionaler Fehlschlag, aber ein Wartungsdefizit.
- MechanicCoverage meldet 38 Signale ohne Testmodelle; die Chronik-Live-Projektion sollte dafür eigene strukturelle Tests erhalten.
- Ein beschädigter Test-Save in `user://saves/run_2.tres` erzeugt erwartete Parse-Fehler beim Slot-Test. Der Slot-Constraint bleibt PASS, aber der Testzustand sollte bereinigt werden, ohne Slot 0 anzutasten.

## 9. Gap-Matrix gegen den Ziel-Scope

| Ziel | Status | Root Cause / nächster Schnitt |
|---|---|---|
| Simulation statt Lore | implementiert | `HistorySimulator` ist autoritativ für Backstory-Facts |
| Sprachneutrale Facts | implementiert | `HistoryEvent` + Templates getrennt |
| 300 Jahre | implementiert | `SIMULATION_YEARS = 300` |
| Figurenbiografien | implementiert | `CharacterBiography` und Lifecycle vorhanden |
| Chains/Kausalität | implementiert | `CauseTracker` + `ChainDetector` |
| Importance | implementiert | `ImportanceEvaluator` |
| DE/EN | implementiert | 36 Templates je Locale |
| Gemeinsame Chronik | teilweise implementiert | nur Teilmenge der Live-Events wird HistoryEvent |
| Save/Load | implementiert | `RunSaveData.chronicle` und Roundtrip-Gate |
| Snapshot-Playback | implementiert/testet | noch nicht als Start-Scene verdrahtet |
| SVG-Bausteine | teilweise implementiert | Basis-SVG vorhanden, Entwicklungs-/Objektkomposition fehlt |
| Eigenständige HistoricalWorld-Scene | fehlt | keine Scene und keine SceneDirector-Route |
| Vorstart-Simulation sichtbar | fehlt | Main Menu startet direkt World Scene |
| Wendepunkt-Pause/Kamera | teilweise | Overlay emittiert Banner, kein World-Fokusvertrag |
| Dynamische Fraktionsfilter | fehlt | ArchiveView hard-coded Testfraktionen |
| Erweiterbare Mechanikprojektion | teilweise | EventBus zentral, History-Adapter nicht registry/data-driven |
| Performance/async Start | offen | 300 Jahre synchron beim `run_started`-Event |
| DOKI-Trennung | implementiert | DOKI und Spielchronik sind getrennt |

## 10. Technische Risiken

### R1 — Synchroner Startblock
`WorldChronicle.reset()` simuliert die gesamte Vorgeschichte synchron während des `run_started`-Dispatches. Bei aktuellen Fixtures ist der Lauf akzeptabel, aber die UI kann beim Start mehrere Sekunden blockieren. Ein langfristig stabiler Fix ist ein chunkbarer/inkrementeller Simulatorlauf oder ein Background-Worker mit deterministischer Übergabe; ein bloßes längeres Timeout wäre kein Fix.

### R2 — Snapshot ist zu dünn für die Zielvisualisierung
Ownership allein kann keine sichtbaren Fortschrittsbausteine darstellen. Der Snapshot braucht ein versioniertes `visual_state`-Modell, das aus WorldState abgeleitet wird und niemals neue Wahrheit erzeugt.

### R3 — Live-Faktenverlust
Viele GameState-Signale verschwinden derzeit in EventLog/UI, ohne in der Chronik als HistoryEvent zu landen. Ein zentraler typisierter Event-Adapter verhindert, dass jede neue Mechanik WorldChronicle direkt ändern muss.

### R4 — UI-Testdaten im Produktionspfad
Hard-coded Fraktionen in `ChronicleArchiveView` brechen den eigentlichen Run-Vertrag. Das muss vor jeder sichtbaren Chronikabnahme behoben werden.

### R5 — Zufälliger Layout-Seed
Der aktuelle Default-Sektor randomisiert den Layout-Seed. Das ist für normale Runs korrekt, aber die historische Simulation muss den finalisierten Run-Seed verwenden; keine zusätzliche Zufallsquelle darf die historische Folge beeinflussen.

## 11. Priorisierte Roadmap

### Slice A — HistoricalWorld-Startfluss
**Ziel:** Neue eigenständige Scene zwischen Main Menu und World Scene.

- `HistoricalWorld.tscn` mit Renderer, Playback und Overlay.
- `SceneDirector` registriert `historical_world`.
- Main Menu startet bei „Neues Spiel“ zunächst diese Scene.
- Nach `playback_finished` Wechsel zu World Scene mit erhaltenem Run-Kontext.
- Save/Continue überspringt die Vorgeschichte, wenn Chronik bereits gespeichert ist.

**Akzeptanz:** Ein neues Spiel zeigt deterministisch die Vorgeschichte; Skip/Ende führt exakt einmal in die normale Welt; kein zweiter GameState.

### Slice B — Snapshot-Visual-State
**Ziel:** Die Visualisierung zeigt mehr als Ownership.

- Snapshot um versionierte, rein abgeleitete Planet-Visualdaten erweitern.
- SVG-Bausteine anhand von Fortschrittswerten aktivieren.
- Faction-Ring, Kolonie, Industrie, Forschung und Verteidigung darstellen.
- keine direkte Abhängigkeit des Renderers von Simulator oder GameState.

**Akzeptanz:** gleicher Snapshot ergibt byte-/strukturell gleichen Node-Zustand; anderer Snapshot verändert nur Darstellung.

### Slice C — Live-Event-Registry
**Ziel:** Neue Mechaniken liefern automatisch strukturierte Chronikfakten.

- Registry/Adapter für Bus-Eventtypen.
- Pflichtfelder und Event-Typen pro Mechanik.
- klare Unknown-Event-Policy: sichtbar protokollieren, nicht still ignorieren.
- Tests für Besitz, Forschung, Bauen, Ressourcen, Transit, Schiff, Battle und Conquest.

**Akzeptanz:** jedes autoritative Gameplay-Ergebnis erzeugt genau ein deduplizierbares HistoryEvent oder ist explizit als nicht-historisch markiert.

### Slice D — Archiv korrekt an reale IDs binden
**Ziel:** Chronikfilter funktionieren für echte Runs.

- Fraktionsliste aus Events/Initialdaten ableiten.
- Relationsmatrix dynamisch aus `relationships`-Keys aufbauen.
- Planet-/Figurennamen aus Katalog bzw. Biography-Kontext beziehen.
- keine `solari`/`vanguard`/`krypton_miners`-Konstanten im Produktions-UI.

**Akzeptanz:** Lifecycle-Test mit IDs `a`, `b`, `neutral` zeigt korrekte Filter und Beziehungen.

### Slice E — Wendepunkt-Fokus
**Ziel:** Importance wird als World-Interaktion sichtbar.

- Playback liefert beim Überschreiten eines Wendepunkts ein typisiertes Signal.
- HistoricalWorld fokussiert Zielplanet/Region.
- Pause erfolgt nur bei relevanten Events, nicht bei jedem Ticker-Eintrag.
- Benutzer kann fortsetzen, überspringen oder zur Chronik springen.

### Slice F — Historische Startperformance
**Ziel:** lange Vorgeschichten blockieren nicht den Main Loop.

- Simulation in deterministischen Jahres-Chunks ausführen.
- UI zeigt Fortschritt und bleibt kontrolliert interaktiv.
- Snapshot- und Event-Reihenfolge bleibt identisch zum synchronen Referenzlauf.
- Regressionstest vergleicht Chunk-/Sync-Hash.

## 12. Änderungsgrenzen

Die folgenden vorhandenen Verträge dürfen nicht verletzt werden:

- `GameState` bleibt SSOT für Live-Gameplay.
- `WorldState` bleibt temporär und darf nicht in SaveGame als zweite Welt persistiert werden.
- EventBus bleibt die Grenze zwischen Gameplay und Chronik.
- `HistoryEvent` bleibt sprachunabhängig.
- Renderer und Playback konsumieren Snapshots, nicht Simulatorinternals.
- DOKI/Narrative Runtime bleibt vom Spiel-History-System getrennt.
- Slot 0 darf durch Analyse-/Testläufe nicht überschrieben werden.
- neue `class_name`-Skripte benötigen Editor-Scan und `.uid`-Sidecar.

## 13. Schlussfolgerung

Die Aussage „Simulation ist Wahrheit; Text und Visualisierung sind Projektionen“ ist im Kern des Codes bereits umgesetzt. Die nächste sinnvolle Implementierung ist nicht ein weiterer Ausbau der Faction-AI, sondern der sichtbare, eigenständige HistoricalWorld-Flow plus ein vollständiger Visual-State- und Live-Event-Vertrag. Erst damit wird aus dem heute getesteten Chronik-Kern ein tatsächlich erlebbarer Teil von SnipWar.
