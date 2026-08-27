# MCP Autonomy Context & Read-only Audit

**Stand:** 2026-08-25  
**Änderungsmodus:** Dieser Audit ist eine Dokumentation des bisherigen Read-only-Reviews. Er beschreibt keine implementierten Änderungen am MCP.

> **Status-Update 2026-08-27:** Die im Audit als „Lücken" markierten Bereiche sind
> inzwischen größtenteils geschlossen (Belege in `docs/FINDINGS.md`):
> **A (Edit-Workspace)** → `runtime_autonomy_*` journaled Workspace + Gated
> Export; **B (Chain-Modell)** → `runtime_chain_*` mit Versionierung
> (`res://mcp_chains/`); **C (Headless+Visible in einer Chain)** →
> `preflight_constraint`-Subprozess-Schritt; **D (Evidence-Trace)** →
> `McpRunTrace` (`user://mcp_traces/`); **G (Impact-Graph)** bleibt offen
> (Code-Analyzer liefert Muster, keinen vollständigen Impact-Graphen).
> HiGodot bleibt Referenz; die Eigenimplementierung folgt dem bewiesenen Weg.

## 1. Zielbild des Projekts

### Zentrale Arbeitsannahme

Die zentrale Annahme dieses Audits lautet:

> **HiGodot enthält wesentliche Teile einer Editing-, Test- und Diagnose-Schicht für Godot. Wir untersuchen diese Implementierungen und Fehlerfälle als Referenz, übernehmen aber nur eigene Lösungen, die auf unserer Architektur separat bewiesen sind.**

Diese Unterscheidung ist für die Strategie verbindlich:

- **Codebefund:** Die Funktion ist im HiGodot-Clone vorhanden.
- **Problemnachweis:** HiGodot hat einen Fehlerfall reproduziert oder dokumentiert.
- **Qualitätsnachweis:** Verhalten ist automatisiert und live verifiziert.
- **Adaptionsfreigabe:** Unser SnipWar-Tool besteht denselben Nachweis auf unserer Architektur.

Die Deep-Research bestätigt daher nur die Existenz von HiGodot-Funktionen in Script-Editing, Filesystem-Editing, Editor-Mutationen, Undo/Redo, Batch-Rollback, Schreibdiagnostik, Projektstart, Logs und GDScript-Testausführung. Sie bestätigt nicht, dass diese Funktionen fehlerfrei, vollständig, aktuell oder direkt übertragbar sind.

Das MCP soll einem autonomen Coding-/Gameplay-Agenten ermöglichen, den gesamten Entwicklungszyklus ohne laufende Benutzerinteraktion auszuführen:

```text
Projekt analysieren
→ relevante atomare Skripte und Abhängigkeiten finden
→ Testkette zusammensetzen
→ sichtbares Spiel starten
→ UI/UX und Gameplay steuern
→ Freeze / Step zur Reproduktion verwenden
→ Logs, Live-State, Screenshot und OCR auswerten
→ Bug klassifizieren
→ Code oder Ressourcen ändern
→ Änderung speichern
→ identische Reproduktion erneut ausführen
→ abhängige Regressionstests ausführen
→ Ergebnis und Beweise archivieren
```

Der Agent soll auch ohne eigene visuelle Verarbeitung arbeiten können. Dafür soll das MCP die sichtbare Spielsituation sowohl als Bildartefakt als auch als möglichst präzises Text-/UI-Modell bereitstellen. OCR und Image-to-Text ergänzen den autoritativen SceneTree-/Control-Zustand.

## 2. Bereits bestätigt vorhanden

### MCP-Host und Protokoll

- `mcp_server.gd` stellt JSON-RPC über TCP oder stdio bereit.
- Runtime- und Editor-Rolle sind getrennt.
- Runtime und Server laufen mit `PROCESS_MODE_ALWAYS`, damit MCP-Steuerung auch bei Pause möglich bleibt.
- Es existiert eine Async-Queue mit begrenzter Tiefe.
- Der Server besitzt Lifecycle-, Latenz-, Fehler- und Event-Diagnostik.
- Tool-Zugriff wird über Handshake und Rollen-/Write-Gates kontrolliert.

### Registry und Tool-Domänen

`mcp_tool_registry.gd` lädt die Runtime-Tooldomänen lazy und routet über Toolnamen. Bestätigte Bereiche:

- Runtime/Input
- Vision
- Debug
- UX-Pipeline
- E2E
- Playthrough-Archiv
- Game-Systeme
- Code-Analyse
- Goal Player
- Custom Tools aus `res://mcp_tools/`

Die vom Benutzer parallel nachgezogenen acht Registry-Tools und das parallel bearbeitete Response-Filtering sind als laufende Arbeit zu behandeln. Sie wurden in diesem Audit nicht verändert.

### McpGoalPlayer

`mcp_goal_player.gd` ist berücksichtigt und bildet den Gameplay-Agenten-Kern:

1. Input-Methoden statisch analysieren
2. optional Szene laden
3. Spiel einfrieren
4. UI-/Interaktionszustand lesen
5. GDScript-Goal prüfen
6. ersten passenden Interactable anklicken oder `SPACE` senden
7. mehrere Frames steppen
8. Goal erneut prüfen
9. bei Erfolg, Timeout oder Budgetende ein Verdict liefern

Tooloberfläche:

- `runtime_goal_play`
- `runtime_goal_check`
- `runtime_goal_history`

Aktuelle Einschränkung: Der Goal Player ist primär ein heuristischer Gameplay-Loop. Er ist noch kein vollständiger Reparatur-Orchestrator, weil er keinen autoritativen Edit-, Chain- und Regression-Vertrag besitzt.

### Deterministische Eingabe und Freeze

`mcp_input_scheduler.gd` bietet:

- virtuelle Maus
- Blockierung physischer Mausereignisse
- Bounds-Clamping
- verzögerte Mouse-Gesten
- Key-Events
- Drag-Gesten
- Eingabe-Queue
- `runtime_freeze`
- `runtime_unfreeze`
- `runtime_step_frame`
- `runtime_step_frames`
- Freeze-Status und gezählte Frames

Das ist eine gute Basis für reproduzierbare sichtbare Tests.

### Vision, OCR und Textrepräsentation

Vorhanden sind:

- Screenshot-Capture im sichtbaren Renderer
- lokale Context-Artefakte mit TTL und Limits
- Pixel-, Farb-, Template-, Rechteck- und Grid-Analyse
- einfache Textregionenerkennung
- externer Node-Worker mit optionalem Tesseract.js-OCR
- Python-Worker mit optionalem Tesseract-Aufruf
- lokale Artefakte statt Base64-Übertragung
- UI-Transkript aus Live-Control-Daten mit Labels, Rects und Koordinaten

Wichtig: `mcp_ux_text.gd` ist ausdrücklich **kein echtes OCR**. Es liefert nur Muster wie `dense_text`, `sparse_text` oder `few_chars`. Das echte Lesen von Text liegt beim optionalen externen Worker.

### UX-Pipeline

`mcp_ux_pipeline.gd` verbindet:

- autoritativen SceneTree-Control-Snapshot
- visuelle Analyse
- Klassifikation und Gruppierung
- Interactable-Auflösung
- Watch-Modus über Signaturänderungen
- Log-/Anomalieerfassung
- kompakten `agent_context`

Die SceneTree-Daten sind für Klickziele zuverlässiger als reine Pixelklassifikation.

### E2E und Playthrough

Vorhanden sind sichtbare Szenarien für:

- Main Menu
- New Game → World
- Technology-Menü
- Pause/Save/Main Menu
- Forschung
- virtuelle Mausgrenzen
- Freeze/Step
- Codeanalyse und Goal-Check

Zusätzlich existieren:

- `McpTestRunner`
- `.tres`-basierte MCP-Test-Szenarien
- sichtbarer Playthrough Driver
- Playthrough-Archiv mit Frames und GameState-Presets
- externes SQLite-Ledger für Sequenzen, Steps, Screenshots, Checkpoints und Anomalien

### Projektinterne Testbasis

Das Projekt besitzt außerdem:

- `scripts/preflight.gd` als headless Vertrags-/Regressionstest
- einzelne atomare Preflight-Constraints
- `MechanicRegistry`
- `ScenarioLoader` und `ScenarioSnapshot`
- `ConceptIndex`
- `global_search.gd`
- `concept_search.gd`
- deterministische Seeds und isolierte Preflight-Fixtures

## 3. Direkter Vergleich: HiGodot / `hi-godot/godot-ai`

### Identität und Quellenlage

Der direkte Vergleich wurde am 2026-08-25 gegen das separat geklonte Repository durchgeführt:

```text
https://github.com/hi-godot/godot-ai
lokaler Research-Clone: C:/Users/Vannon/Documents/HiGodot-Research/godot-ai
HEAD: 03e74dc870019559535a3f196f1ff24d0ca7a290
Tag-Spitze im Clone: v3.2.0
```

Die folgenden Aussagen sind aus README, `docs/TOOLS.md`, `docs/testing.md`, `docs/tool-surface.md`, dem Plugin-Code, Python-Handlern und Tests abgeleitet. Sie sind keine Vermutungen.

### Was im HiGodot-Clone als Code vorhanden ist

HiGodot beschreibt ungefähr 43 MCP-Tools mit mehr als 120 Operationen. Für dein Ziel besonders relevant:

- `script_create`, `script_read`, `script_patch`, `script_attach`, `script_detach`, `script_find_symbols`
- `filesystem_manage` mit `read_text`, `write_text`, `scan`, `reimport`, `search`
- `scene_manage` mit `create`, `save_as`, `get_roots`
- `scene_open` und `scene_save`
- zahlreiche Node-, Resource-, UI-, Theme-, Animation-, Audio-, Camera- und Input-Operationen
- `batch_execute` mit Undo/Redo-Rollback bei Fehlern
- `project_run` und `project_stop`
- `test_run` für in-editor GDScript-Test-Suites
- `logs_read` für Editor-, Game-, Plugin- und kombinierte Logs
- `editor_screenshot` für Editor- und laufenden Game-Viewport
- MCP-Ressourcen wie `godot://scene/current`, `godot://logs/recent` und `godot://test/results`
- paginierte Antworten, strukturierte Error-Codes und dynamische `tools/list_changed`-Benachrichtigungen

### Antwort auf die zentrale Frage

Die frühere Aussage „HiGodot könnte die fehlende Editing-Schicht liefern“ war zu vorsichtig und als Faktenaussage nicht valide. Nach der Prüfung ist als Codebefund festgehalten:

> **HiGodot enthält eine projektweite Editing-Schicht mit Script-/Filesystem-Editing, Schreibdiagnostik und Batch-Rollback. Ob diese Schicht unsere Qualitäts- und Autonomieanforderungen erfüllt, ist erst nach unserem eigenen Nachweis entschieden.**

Das bedeutet nicht, dass HiGodot automatisch unser komplettes Ziel erfüllt. Ebenso werden unsere Runtime-Bausteine nicht pauschal als besser bewertet, sondern nur im jeweils geprüften Funktionsbereich: virtuelle Mausisolation, Freeze/Step, Goal Player, sichtbare E2E-Szenarien, OCR-Artefakte und GameState-Playthrough-Presets.

### Verifizierte HiGodot-Editing-Muster

1. **Script-Editing:** `.gd`-Dateien können erstellt, gelesen, gepatcht und Nodes zugewiesen werden.
2. **Filesystem-Editing:** Textdateien werden projektbezogen geschrieben; danach existieren Scan-/Reimport-Schritte für Godot-Dateisystemzustand.
3. **Atomare Editoraktionen:** Node-/Resource-/Animation-/UI-Änderungen werden über `EditorUndoRedoManager` modelliert.
4. **Batch-Rollback:** `batch_execute` stoppt am ersten Fehler und rollt erfolgreiche Undo-fähige Teilaktionen zurück.
5. **GDScript-Diagnostik:** `script_create` und `script_patch` validieren Inhalt vor/bei der Editor-Importphase und geben strukturierte `diagnostics` zurück.
6. **Testausführung:** `test_run` entdeckt `McpTestSuite`-Dateien in `res://tests/`, führt sie aus und liefert Pass/Fail/Skip, Ladefehler und Details.
7. **Laufzeitübergang:** `project_run` startet das Projekt und wartet auf Game-Liveness; bei Parse-/Load-Fehlern werden strukturierte Hinweise geliefert.
8. **Response-Reduktion:** Antworten können gezielt Felder, Seiten, Details und Cursor verwenden; Logs und große Datenmengen sind nicht grundsätzlich unlimitiert.
9. **Serverarchitektur:** Python/FastMCP dient als MCP-Frontend; das Godot-Plugin kommuniziert über WebSocket mit Editor-/Runtime-APIs.

### HiGodot-Einschränkungen für dein Ziel

Auch HiGodot ist nicht automatisch ein vollständiger autonomer Repair-Agent:

- `test_run` ist ein GDScript-Testframework und keine allgemeine Gameplay-Chain.
- Laut Testdokumentation sind Testmethoden synchron; Szenenwechsel und Start/Stop innerhalb eines Tests sind eingeschränkt.
- `batch_execute` ist nicht für deferred/lang laufende Testpfade geeignet; `test_run` muss direkt aufgerufen werden.
- Der Clone dokumentiert bekannte verbleibende Timeout-, Import-, Reload-, Concurrency- und Handler-Risiken.
- Die eigentliche Reasoning-/Repair-Schleife bleibt Aufgabe des angeschlossenen Agents.
- OCR/visuelle Textinterpretation ist nicht der Kern der Editing-Schicht und muss separat bewertet werden.
- HiGodot verwendet eine externe Python-/WebSocket-Architektur, während unser MCP derzeit einen Godot-internen TCP/stdio-Host verwendet. Eine direkte Codeübernahme wäre daher nicht ohne Architekturentscheidung möglich.

### Vergleichsmatrix

| Fähigkeit | Unser MCP, geprüft | HiGodot, geprüft | Bedeutung |
|---|---:|---:|---|
| SceneTree-/Node-Inspektion | Ja | Ja | kein Differenzierer |
| Node-/Property-Editing | Ja | Ja | beide brauchbar |
| `.gd` erstellen/lesen/patchen | Nicht vollständig bestätigt | Ja | HiGodot-Vorsprung |
| beliebige Textdateien schreiben | Nicht vollständig bestätigt | Ja | HiGodot-Vorsprung |
| Undo/Redo für Editoraktionen | Ja | Ja | vergleichbar |
| atomarer Multi-Command-Rollback | nicht als allgemeiner Vertrag bestätigt | Ja | HiGodot-Vorsprung |
| GDScript-Schreibdiagnostik | nicht gleichwertig bestätigt | Ja | HiGodot-Vorsprung |
| eingebautes GDScript-Testframework | Preflight/MCP-Szenarien vorhanden | Ja | unterschiedliche Modelle |
| sichtbares Gameplay | Ja | teilweise über Game-Tools/Screenshot | unser Vorsprung |
| Freeze/Step deterministisch | Ja | nicht als gleichwertiger Kern belegt | unser Vorsprung |
| virtuelle Mausisolation | Ja | nicht gleichwertig belegt | unser Vorsprung |
| OCR/Image-to-text-Pipeline | Ja, optional | nicht als gleichwertiger Kern belegt | unser Vorsprung |
| Goal-basierter autonomer Player | Ja | nicht als gleichwertiger Kern belegt | unser Vorsprung |
| GameState-Presets/Playthrough-Archiv | Ja | Testresultate/Ressourcen, anderes Modell | unser Vorsprung in Gameplay-Kontext |
| MCP-Ressourcen | nicht als vollständige MCP-Ressource bestätigt | Ja | HiGodot-Vorsprung |
| Tool-List-Change-Notifications | derzeit nicht konsistent bestätigt | Ja | HiGodot-Vorsprung |
| End-to-end Repair Loop | nicht vollständig | nicht automatisch vollständig | gemeinsame Lücke |

### Strategische Schlussfolgerung

Die sinnvollste Zielrichtung ist **beweisgesteuerte Eigenimplementierung auf Basis geprüfter HiGodot-Referenzen**, nicht blinde Codekopie. Die Arbeitsteilung lautet:

```text
HiGodot: Referenzcode und reproduzierte Problemverträge
+ eigene Workspace-/Editing-/Validation-Tools
+ unser Runtime Goal Player
+ unser Freeze/Step-System
+ unsere Vision/OCR-/Evidence-Schicht
+ Chain Planner und Repair Orchestrator
= autonomer Godot-Entwicklungsagent
```

Der konkrete Adaptionsauftrag lautet:

1. HiGodots Editing- und Testverträge extrahieren.
2. Prüfen, welche Teile als Godot-native Konzepte direkt in unser MCP passen.
3. Nur die fehlenden oder inkompatiblen Teile neu bauen.
4. HiGodots Schreibdiagnostik, Rollback- und Testmuster gegen unsere Response-Filter und Registry-Verträge abgleichen.
5. Danach die Editing-Schicht mit unserem Goal Player und den sichtbaren Gameplay-Chains verbinden.

HiGodot ist damit eine wichtige Referenz für den fehlenden Editing-Kern und für reale Fehlerklassen. Vor jeder eigenen Implementierung müssen Lizenz, API-Kompatibilität, Prozessmodell, Sicherheitsgrenzen, Versionierung und die Eigentümerschaft des MCP-Servers geklärt werden. Vor dem lokalen Gate gilt kein Baustein als „bewährt“.

## 4. Sicher festgestellte Lücken

### A. Kein vollständiger MCP-Quellcode-Editkanal

Die Editor-Tools können Nodes, Properties, Ressourcen und Szenen bearbeiten. Ein klarer MCP-Workflow für beliebige Projektdateien ist im geprüften Stand nicht als vollständiger Vertrag sichtbar:

- Datei lesen mit Version/Hash
- gezielten Patch anwenden
- Diff zurückgeben
- atomar speichern
- Rollback ermöglichen
- Projektpfade absichern
- Syntax-/Resource-Validierung danach ausführen

Das ist für autonome Code-Reparatur zwingend.

### B. Kein deklaratives Chain-Modell

Die E2E-Szenarien sind überwiegend fest codierte Methoden. Es fehlt ein allgemein gültiges Manifest, das Testschritte aus atomaren Skripten, Mechaniken und Abhängigkeiten zusammensetzt.

Benötigte minimale Kette:

```text
Precondition
→ Action
→ Observation
→ Assertion
→ Evidence
→ Verdict
→ Checkpoint / Rollback
```

### C. Headless- und Visible-Testmodus sind nicht als eine Chain verbunden

Headless wird für Preflight und statische/Logiktests benötigt. Visible wird für Renderer, Input, UI/UX, Screenshot und OCR benötigt. Die Infrastruktur kennt beide Bereiche, aber ein einzelner autonomer Lauf kann sie noch nicht als einen versionierten Ablauf koordinieren.

### D. Kein gemeinsamer Evidence-Trace

Frames, Presets, JSONL-Archiv, MCP-Lifecycle und SQLite-Ledger existieren, aber der Audit konnte keinen einheitlichen Beweisdatensatz bestätigen, der alle folgenden Werte bindet:

- Code-/Datei-Hash vor und nach dem Patch
- Chain-/Step-ID
- Eingabeereignis
- SceneTree-Zustand
- GameState-Fingerprint
- Screenshot-/OCR-Artefakt
- Log-Delta
- Tool-Result
- Verdict
- getestete Regressionen

### E. Goal Player ist noch heuristisch

Der Goal Player klickt typischerweise den ersten geeigneten Interactable. Das ist für Exploration brauchbar, aber für Bug-Reproduktion und Reparatur nicht ausreichend stabil. Für Reparaturketten braucht jede Aktion eine stabile Zielidentität, Precondition und erwartete Zustandsänderung.

### F. Response-Filtering muss als Vertrag geprüft werden

Die bisher sichtbare Sanitization entfernt problematische Objekte bzw. Bildmarker. Für autonome Agents sind zusätzlich erforderlich:

- valide `outputSchema`
- stabile Ausgabeformate
- Größenbudgets
- Cursor-/Pagination-Unterstützung
- explizite Truncation-Marker
- konsistente Fehlerstruktur
- getrennte Beobachtungen und Artefakte
- Pfad-/Secret-Filter
- deterministische Sortierung
- Response-Versionierung

Die acht parallelen Registry-Tools müssen jeweils in Definition, Routing, Dispatch und Response-Filter geprüft werden.

### G. Codeanalyse liefert noch keinen vollständigen Impact-Graphen

Der Code Analyzer erkennt Textmuster, Signale, Szenen, Autoloads und GameState-Methoden. Für autonome Reparatur fehlen als verbindlicher Output noch:

- exakte Zeilenbereiche
- Klassen- und Methodensymbole
- Preload-/Load-Abhängigkeiten
- Aufrufer und Verbraucher
- betroffene Preflight-Constraints
- betroffene atomare Change-Gruppen
- betroffene Szenarien

## 5. Vergleichbare Konzepte

### MCP

MCP definiert Tool-Discovery und Tool-Aufrufe, aber nicht automatisch Software-Reparatur, Chain-Orchestrierung oder Rollback. Diese Schichten müssen projektseitig ergänzt werden.

### OpenHands

OpenHands trennt Agent, Workspace, Tools, Events und Sicherheitsrichtlinien. Das ist ein gutes Vorbild für eine klare Trennung von Godot-Runtime, Editor, Dateisystem, Testorchestrator und Agentenledger.

### SWE-agent

SWE-agent ist relevant für den Zyklus Lokalisieren → Patchen → Testen → Bewerten. Für dieses Projekt muss das um sichtbares Gameplay und Bild-/OCR-Beweise erweitert werden.

### Playwright Trace

Playwright verbindet Aktion, DOM-/Accessibility-Zustand, Screenshot, Netzwerk-/Fehlerinformationen und Testschritt in einem Trace. Für dieses MCP ist das wahrscheinlich das wichtigste Vorbild für einen vollständigen Evidence-Record.

## 6. Vermutungen und noch nicht bewiesene Annahmen

Die folgenden Punkte sind **Hypothesen**, keine bestätigten Fakten:

1. Die acht parallel nachgezogenen Registry-Tools sind möglicherweise bereits vollständig in einer nicht sichtbaren Arbeitskopie vorhanden. Im aktuellen Git-Stand war kein Diff sichtbar, deshalb konnte ihre tatsächliche Einbindung nicht geprüft werden.
2. Das Response-Filtering könnte in deiner parallelen Version bereits über die sichtbare `_sanitize_result()`-Logik hinausgehen. Das muss gegen die tatsächlich aktuelle Datei geprüft werden.
3. HiGodots Editing- und Testbausteine lassen sich wahrscheinlich direkt oder mit überschaubarem Adapteraufwand in unser MCP überführen. Das ist die zentrale Adaptionshypothese; sie ist noch nicht durch einen PoC bewiesen.
4. Die bestehenden atomaren Preflight-Constraints sollen vermutlich die Bausteine für dynamische Testketten liefern. Derzeit ist nicht bewiesen, dass jedes Constraint über einen einheitlichen maschinenlesbaren Vertrag verfügt.
5. Der externe Vision-Worker wird vermutlich lokal verfügbar sein oder vom Agenten gestartet werden können. Im Repository sind Worker-Skripte vorhanden, aber OCR-Abhängigkeiten und Startvoraussetzungen sind nicht garantiert.
6. „1:1 nachvollziehbar“ bedeutet wahrscheinlich eine Kombination aus Screenshot, OCR/Texttranskript, Control-Rect, Input-Event und GameState. Ein verbindlicher Genauigkeitsmaßstab wurde noch nicht festgelegt.
7. Für autonome Reparatur wird vermutlich ein isolierter Workspace oder Branch/Snapshot benötigt. Im MCP selbst ist ein kompletter Workspace-Rollback noch nicht bestätigt.
8. Die gewünschte Autonomie könnte mit einem expliziten `autonomous_repair`-Profil vereinbar sein, obwohl MCP aus Sicherheitsgründen normalerweise Human-in-the-loop empfiehlt. Dafür braucht es klare Schreib- und Prozessgrenzen.

## 7. Priorisierte Zielarchitektur

### Phase 1: Autonomy Contracts

- stabiler `Run`, `Chain`, `Step`, `Evidence`, `Verdict`-Vertrag
- einheitliche Fehler- und Response-Schemas
- Tool-Metadaten für read/write, visible/headless, sync/async, mutating/non-mutating

### Phase 2: Edit Workspace

- MCP-Dateiread mit Hash
- atomarer Patch
- Diff
- Validierung
- Rollback
- explizites Save/Commit-Artifact

### Phase 3: Chain Planner

- atomare Scripts und Preflight-Constraints discovern
- Abhängigkeiten und betroffene Mechaniken bestimmen
- headless und visible Schritte in einer Chain verknüpfen
- Checkpoints und Retry-Regeln festlegen

### Phase 4: Reproduction and Repair Loop

```text
Baseline
→ Freeze
→ Action
→ Step
→ Observe
→ Classify
→ Patch
→ Validate
→ Repeat exact reproduction
→ Regression chain
```

### Phase 5: Evidence and Learning

- ein Trace pro Run
- Frames/OCR/SceneTree/GameState/Logs/Diffs zusammenführen
- erfolgreiche Scripts versioniert archivieren
- fehlgeschlagene Versuche und MCP-Probleme getrennt speichern

## 8. Adaptionsqualität und Beweisstandard

Für die weitere Arbeit gilt eine strengere Regel als „HiGodot hat es implementiert“:

> **Wir adaptieren nur Bausteine, deren Verhalten auf unserer Architektur durch Code-, Test-, Fehler- und Live-Nachweis bestätigt ist.**

Ein HiGodot-Commit oder ein historisch behobener Bug ist ein Referenzhinweis. Er ist kein Beweis, dass die Implementierung vollständig, aktuell, robust oder in SnipWar übertragbar ist.

### Zulassungskriterien

Ein Baustein darf erst als bewährt gelten, wenn:

1. die aktuelle Implementierung und ihre Grenzen gelesen wurden,
2. ein automatischer Test Erfolg, Fehler und Grenzfälle prüft,
3. der Fehlerfall reproduzierbar belegt ist,
4. ein isolierter Headless- und bei Runtime-Funktionen ein echter Visible-Smoke bestanden ist.

Bis dahin lautet der Status ausschließlich **Referenzkandidat**.

### Nicht übernehmen, sondern sauber ersetzen

Interne HiGodot-Workarounds werden nicht kopiert. Für unser MCP sind eigene Verträge vorgesehen:

- Import-Rennen werden durch eine begrenzte Resource-Readiness-Barrier gelöst, nicht durch beliebige Sleeps.
- Dateisystem-Rollback läuft über ein Workspace-Journal mit Hashes und Preimages, nicht über Editor-Undo.
- Lange Testläufe laufen über einen eigenen Job-/Partial-Result-Vertrag, nicht in einem synchronen Edit-Batch.
- Filesystem-Zustand wird inkrementell invalidiert und nur bei Bedarf per Scan-Barriere synchronisiert.
- Unvollständige Diagnostics werden als `partial` oder `unavailable` markiert, nie als Erfolg behandelt.
- Response-Filtering liefert ein versioniertes Schema mit Größenbudget und `truncated`-Hinweis, nicht nur Feldlöschung.
- Reload-Sicherheit wird über Lifecycle-Generationen und Besitznachweise gelöst, nicht über fragile Reihenfolgen allein.

Die vollständige Klassifikation und die genaue Nachweis-Matrix stehen in [HIGODOT_ADAPTATION_ANALYSIS.md](HIGODOT_ADAPTATION_ANALYSIS.md).

## 9. Kurzfazit

Die konkrete HiGodot-Analyse und Adaptionskarte steht in [HIGODOT_ADAPTATION_ANALYSIS.md](HIGODOT_ADAPTATION_ANALYSIS.md). Sie ist als Beweis- und Implementationsanalyse angelegt, nicht als Refactorauftrag.

Die zentrale Strategie lautet:

```text
HiGodot als Referenz und Fehlerkatalog prüfen
+ eigene Editing-/Testing-/Validation-Verträge bauen
+ unser Goal Player
+ unser Freeze/Step
+ unsere Vision/OCR-/Evidence-Schicht
+ Chain-/Repair-Orchestrierung
```

Der Goal Player ist vorhanden und wichtig. Die Vision-/OCR-, Freeze-, E2E-, Preflight- und Archivbausteine sind ebenfalls vorhanden. Der größte Abstand zum Ziel liegt nicht im grundlegenden Gameplay-Steuern, sondern in der verbindlichen Kopplung von:

```text
Edit Workspace + Chain Planner + Evidence Trace + Repair Loop
```

Dieses Dokument ist eine Wissens- und Annahmenbasis für die nächste Read-only-Analyse. Es enthält keine Implementierungsentscheidung, die ohne weitere Prüfung als bereits umgesetzt gelten darf.
