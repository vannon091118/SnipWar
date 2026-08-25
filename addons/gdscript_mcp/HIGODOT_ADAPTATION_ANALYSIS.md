# HiGodot → SnipWar MCP: Adaptions- und Implementationsanalyse

**Stand:** 2026-08-25  
**Research-Repository:** `https://github.com/hi-godot/godot-ai`  
**Lokaler Clone:** `C:/Users/Vannon/Documents/HiGodot-Research/godot-ai`  
**Geprüfter HEAD:** `03e74dc870019559535a3f196f1ff24d0ca7a290`  
**Geprüfter Tag:** `v3.2.0`

## Ziel dieser Analyse

Dies ist kein Refactor-Plan. Das Ziel ist eine **Beweis- und Implementationskarte**, damit wir HiGodot als Referenz für Editing-/Testing-Probleme nutzen, ohne ungeprüfte Workarounds zu übernehmen.

Die präzise Arbeitsannahme lautet:

> HiGodot enthält wesentliche Editing-/Testing-Funktionen und dokumentierte Fehlerbehebungen. Das beweist die Existenz von Code und Problemverträgen, aber noch nicht deren Qualität, Vollständigkeit oder Übertragbarkeit. Jede Adaption muss in unserem MCP separat bewiesen werden.

## 1. Was können wir schon?

### Unser MCP kann bereits

| Bereich | Vorhandene Fähigkeit |
|---|---|
| Runtime-Steuerung | SceneTree lesen, Nodes inspizieren, UI finden und klicken |
| Input | virtuelle Maus, Mouse-Isolation, Keys, Drag, Input-Queue |
| Determinismus | Freeze, einzelner Frame, mehrere zusammenhängende Frames |
| Gameplay | `McpGoalPlayer`, Goal-Ausdrücke, sichtbare E2E-Szenarien |
| UX | Live-Control-Snapshot, Rects, Interactables, visuelle Analyse, Watch-Modus |
| Vision | Screenshot-Artefakte, Pixel/Farbe/Template/Rect/Grid-Analyse |
| OCR | optionaler Node-/Python-Worker, lokale Artefakte statt Base64 |
| Projektverständnis | Code Analyzer, ConceptIndex, Global Search, GameState-Analyse |
| Projekt-Regression | Headless Preflight mit atomaren Constraints und Fixtures |
| Szenariozustände | GameState-Snapshots, Playthrough-Frames und Presets |
| Archivierung | Playthrough-Archiv und externes Agenten-Ledger |
| Editor | Node-/Property-/Resource-Änderungen, Undo/Redo, Scene-Save |
| Runtime-Systeme | Audio, Animation, Gamepad/Touch, Shader/Particles, Netzwerk-Hooks |

### Was davon bereits agentisch brauchbar ist

Der Runtime-Teil ist für einen Agenten bereits gut nutzbar, weil er nicht nur rohe Koordinaten anbietet, sondern:

- sichtbare Controls über den SceneTree autoritativ findet,
- Aktionen als Input-Gesten in Frames einplant,
- Pausen und Übergänge kontrolliert,
- Screenshots lokal als Artefakte ablegt,
- GameState und UI gemeinsam beobachten kann,
- E2E-Ergebnisse und Anomalien zurückliefert.

Der `McpGoalPlayer` ist damit ein vorhandener Gameplay-Agent-Kern, aber noch kein Editor-Reparatur-Agent.

## 2. Was ist in HiGodot als Referenzcode vorhanden?

Die folgenden Punkte sind zunächst **Codebefunde**, keine Freigaben. „Vorhanden“ bedeutet: im geprüften Clone gefunden. „Nachweislich gut“ bedeutet erst: unser Adaptions-Gate in Abschnitt 8.4 ist bestanden.

### 2.1 Script-Editing

HiGodot besitzt nachweislich:

- `script_create`
- `script_read`
- `script_patch`
- `script_attach`
- `script_detach`
- `script_find_symbols`

Der wichtigste Baustein ist `script_patch(path, old_text, new_text, replace_all)`. Dadurch wird ein Patch an erwarteten Ausgangstext gebunden, statt eine Datei blind vollständig zu überschreiben.

Zusätzlich validiert HiGodot geschriebene GDScript-Inhalte und liefert:

- `diagnostics`
- `diagnostics_scope`
- `diagnostics_status`
- `diagnostics_detail`
- fallback line information, wenn Godot keine vollständigen Loggerdetails liefert

**Prüfauftrag:** Den Patch-Vertrag in einem isolierten SnipWar-PoC gegen Hash-Konflikte, Mehrfachtreffer, Nicht-Existenz, UID-Nebenwirkungen und Syntaxfehler prüfen. Erst nach bestandenem Gate darf daraus ein eigenes Tool werden. Die HiGodot-Serverarchitektur wird nicht übernommen.

### 2.2 Filesystem-Editing

HiGodot unterscheidet korrekt zwischen:

- beliebigem Textschreiben über `filesystem_manage(op="write_text")`
- GDScript-Schreiben mit zusätzlichen Parse-Diagnostics
- `update_file()` für einzelne Pfade
- explizitem Full-Scan für neue `class_name`-Registrierungen
- Asset-Reimport nur dort, wo eine `.import`-Nebenstruktur existiert

Besonders wichtig ist die Vermeidung eines Full-Scans nach jedem einzelnen Script-Write. HiGodot nutzt einen einzelnen Update-Pfad und reserviert den teureren Scan für einen expliziten Schritt.

**Prüfauftrag:** Das inkrementelle Update-/Scan-Modell gegen unsere Godot-internen Import- und Indexverträge prüfen. Ziel ist ein eigenes, explizites Tooling statt einer übernommenen Scan-Heuristik:

```text
write/patch
→ per-file validation
→ per-file update
→ optionaler gebündelter class-scan
→ erst danach abhängige Tests
```

### 2.3 Atomare Batch-Edits

HiGodot bietet `batch_execute`:

- Stop-on-first-error
- maximal begrenzte Befehlszahl
- Vorvalidierung der Befehle und Parametertypen
- verbotene deferred Subcommands
- Undo/Redo-Rollback erfolgreicher vorheriger Editoraktionen
- Ergebnis pro Subcommand
- `succeeded`, `stopped_at`, `rolled_back`, `undoable`
- Fuzzy Suggestions bei unbekannten Befehlen

Wichtig ist die Trennung:

- Editor-Undo-fähige Node-/Resource-Aktionen können in einen Batch.
- lange oder deferred Test-/Gameplay-Aktionen gehören nicht in denselben synchronen Batch.

**Prüfauftrag:** Den Unterschied zwischen Editor-Undo und Datei-Transaktionen in einem roten Rollback-Test festlegen. Für unser MCP wird daraus nur ein eigener Transaction-Vertrag; sichtbare Runtime-Aktionen bleiben außerhalb synchroner Editor-Batches.

### 2.4 Test-Runner und Testdiagnostik

HiGodot besitzt ein eigenes `McpTestSuite`-Modell und `test_run`:

- Suite-Discovery unter `res://tests/`
- Suite-/Test-Filter
- Pass/Fail/Skip
- Ladefehler pro Datei
- Zero-Assertion-Erkennung
- Script-Error-Capture
- Test-Isolation und Cleanup
- partielle Ergebnisse bei Timeout
- zwischen Testphasen serviced Transport
- explizite `TEST_RUN_TIMEOUT`- und `EDITOR_TEST_RUNNING`-Zustände
- letzte Ergebnisse über `test_manage(op="results_get")`

**Prüfauftrag:** HiGodots Resultatform gegen unsere Preflight-Constraints und den Goal Player kontrastieren. Das Preflight-System wird nicht ersetzt; eine gemeinsame Chain-Schnittstelle darf erst nach Ergebnis- und Timeouttests entstehen:

```text
Preflight = Projektverträge und deterministische Logik
McpTestSuite = agent-erzeugte/agent-nahe Editor-Tests
McpGoalPlayer = sichtbares Gameplay
```

Diese drei Testarten müssen später über eine gemeinsame Chain referenzierbar sein.

### 2.5 Projektstart und Liveness

HiGodot liefert bei `project_run` mehr als „play gedrückt“:

- `game_status`
- `helper_live`
- `session_active`
- `was_already_running`
- `recent_errors`
- `break`-Status bei Debugger-Parse-/Load-Fehlern

Es unterscheidet Start, laufendes Spiel, fehlenden Helper, Parse-Break und nicht reagierenden Prozess.

**Prüfauftrag:** Einen eigenen Start-/Liveness-Receipt für unseren Runtime-Host definieren und gegen Parse-Fehler, fehlenden Helper, bereits laufendes Spiel und hängenden Prozess testen. HiGodots Receipt wird nur als Referenz für Zustandsabdeckung verwendet.

### 2.6 Logs, Cursor und Response Filtering

HiGodot hat eine ausgearbeitete Antwortstrategie:

- strukturierte Error-Codes
- Logs mit Cursor und Pagination
- `include_details` als teurere Option
- `new_errors_since_last_call`
- Hinweise auf die richtige nächste Diagnoseaktion
- explizite Truncation-/Stale-Cursor-Zustände
- unterschiedliche Response-Budgets für normale und ausführliche Antworten
- `tools/list_changed` bei dynamischen Tools
- MCP-Ressourcen für read-heavy Informationen
- Middleware zur Erhaltung strukturierter Godot-Fehlerdaten

**Prüfauftrag:** Die parallele Registry-/Filtering-Arbeit gegen ein versioniertes Observation-Schema testen. Response-Filtering darf keine Daten nur „wegoptimieren“; es muss Vollständigkeit, Truncation, Artefaktverweise und Fehlerstatus explizit ausweisen.

## 3. Wo passt das in unser System?

### Zielmapping

```text
HiGodot Concept                  Unser Zielort
──────────────────────────────────────────────────────────────
script_create/read/patch         neue Project/Edit-Schicht
filesystem write/scan            Project/Edit-Schicht + Context/Index
batch_execute/rollback           Transaction-Schicht
script diagnostics               Validation-/Response-Schicht
project_run/liveness             Runtime Host + Lifecycle
logs_read/cursors                Lifecycle + UX/Diagnostics
McpTestSuite/test_run            Test-Chain-Adapter
MCP resources                    Context-/Observation-Schicht
```

### Konkrete Einbaupunkte

1. `mcp_tool_registry.gd`
   - neue Edit-/Project-/Test-Tooldefinitionen registrieren
   - Werkzeugmetadaten ergänzen: `read`, `write`, `visible`, `headless`, `async`, `rollback`
   - acht parallele Registry-Tools dort vollständig routen

2. `mcp_server.gd`
   - Schreibrechte und Projektpfad-Grenzen an einer Stelle erzwingen
   - Response-Filtering nach Tooltyp ausführen
   - Async-Edits/Testläufe nicht mit synchronen Runtime-Batches blockieren

3. `mcp_project_adapter.gd`
   - Projekt-/GameState-Fingerprint erweitern
   - Edit-Impact und Snapshot-Handover an einen gemeinsamen Run-Record anbinden

4. `mcp_lifecycle.gd`
   - Edit-/Test-/Runtime-Phasen als Zustände sichtbar machen
   - Liveness, Busy, Timeout, Rollback und Evidence-Cursor erfassen

5. `mcp_goal_player.gd`
   - nicht ersetzen
   - um stabile Step-IDs, Preconditions, erwartete Deltas und Chain-Kontext erweitern

6. `mcp_playthrough_archive.gd`
   - bestehende Frames/Presets um Edit-Diff, Testresultat und Code-Fingerprint ergänzen

7. `scripts/preflight.gd` und atomare Constraints
   - nicht ersetzen
   - als Headless-Chain-Schritte referenzierbar machen

8. `mcp_ux_pipeline.gd` und Vision-Worker
   - als Visible-Observation-Schicht verwenden
   - OCR nicht als Ersatz für SceneTree-Daten, sondern als zusätzliche Evidenz behandeln

## 4. Wie arbeitet das mit den aktuellen MCP-Schichten zusammen?

### Bestehender Datenfluss

```text
Agent
  ↓ JSON-RPC
McpServer
  ↓ Registry
McpToolRegistry
  ├─ RuntimeTools → Input / Freeze / Step / Eval
  ├─ UXPipeline   → SceneTree / Interactables / UI
  ├─ Vision       → Screenshot / OCR / Pixel
  ├─ E2E          → feste sichtbare Szenarien
  ├─ GoalPlayer   → heuristisches Goal-Spiel
  ├─ Archive       → Frames / Presets / Erfolge
  └─ Debug        → Logs / Perf / Engine
```

### Optimierter Datenfluss mit adaptierter HiGodot-Schicht

```text
Agent
  ↓
Autonomy Run / Chain Controller
  ├─ Project Analysis
  ├─ Edit Transaction
  │    ├─ read/patch/create
  │    ├─ diagnostics
  │    ├─ filesystem update/scan
  │    └─ rollback
  ├─ Headless Validation
  │    ├─ preflight constraints
  │    ├─ McpTestSuite/test_run
  │    └─ dependency-selected tests
  ├─ Visible Runtime Validation
  │    ├─ project liveness
  │    ├─ GoalPlayer
  │    ├─ Freeze/Step
  │    ├─ UX/SceneTree
  │    └─ screenshot/OCR
  └─ Evidence Record
       ├─ hashes/diff
       ├─ state fingerprints
       ├─ logs
       ├─ screenshots/OCR
       └─ verdict/rollback/retry
```

Die neue Editing-Schicht sitzt somit **vor** den bestehenden Runtime-Schichten und liefert ihnen eine versionierte, getestete Projektbasis. Sie ersetzt weder Goal Player noch Vision noch Preflight.

## 5. Wie implementieren wir das agentenoptimiert?

### 5.1 Tooltypen statt unklarer Einzelaktionen

Jede neue oder adaptierte Operation braucht maschinenlesbare Metadaten:

```json
{
  "mutates_project": true,
  "requires_editor": true,
  "requires_visible_renderer": false,
  "supports_rollback": true,
  "may_defer": true,
  "response_mode": "receipt_plus_diagnostics"
}
```

Damit kann der Agent selbst erkennen, welche Aktionen in welcher Phase erlaubt sind.

### 5.2 Optimierter Agentenfluss

```text
1. index/context lesen
2. Projekt- und Impact-Analyse
3. passenden HiGodot-adaptierten Editpfad wählen
4. Baseline-Fingerprint aufnehmen
5. Patch mit expected_old_text/hash anwenden
6. per-write Diagnostics auswerten
7. gebündelten Filesystem-Scan nur bei Bedarf ausführen
8. betroffene Headless-Tests bestimmen
9. sichtbares Spiel starten und Liveness prüfen
10. Goal-/Gameplay-Chain ausführen
11. Freeze/Step bei Fehlern
12. Live + Bild + OCR + Logs vergleichen
13. MCP_ISSUE oder GAME_ISSUE klassifizieren
14. bei GAME_ISSUE neuen Patch anwenden
15. identische Reproduktion wiederholen
16. abhängige Regressionen ausführen
17. Evidence und funktionierendes Script archivieren
```

### 5.3 Response-Form für autonome Entscheidungen

Jeder mutierende Schritt sollte kompakt, aber vollständig antworten:

```json
{
  "ok": true,
  "operation": "script_patch",
  "path": "res://...",
  "before_hash": "...",
  "after_hash": "...",
  "changed": true,
  "diagnostics": [],
  "filesystem": {"updated": true, "scan_required": false},
  "rollback": {"available": true, "token": "..."},
  "next": ["run_affected_tests", "start_visible_validation"]
}
```

Bei Fehlern:

```json
{
  "ok": false,
  "verdict": "MCP_ISSUE|GAME_ISSUE|VALIDATION_ERROR|BLOCKED",
  "error": {"code": "...", "message": "..."},
  "diagnostics": [],
  "rollback": {"performed": true},
  "next": ["inspect_logs", "retry_after_scan"]
}
```

### 5.4 Keine unnötige Tool-Explosion

HiGodot bündelt viele Operationen über Domain-Rollups, behält aber für häufige Aktionen direkte Tools. Für unser MCP sollte gelten:

- häufige Agentenaktionen als direkte, stabile Tools
- seltene Godot-Spezialaktionen als Domain-Rollup
- Chain-Operationen als eigener Orchestrator, nicht als 100 Einzelaufrufe vom Agenten
- Response-Filtering verhindert, dass große Godot-Objekte den Kontext überfüllen

### 5.5 Headless/Visible als explizite Chain-Schritte

Ein Testschritt muss deklarieren:

```text
mode: headless | visible
requires: renderer | editor | game | none
```

Beispiele:

```text
script_patch       → headless/editor
preflight          → headless
project_run        → visible/editor
runtime_goal_play  → visible/game
runtime_screenshot → visible/game
```

Damit versucht der Agent nicht, OCR in Headless auszuführen oder einen Renderer für reine Datenvalidierung zu booten.

## 6. Was wir ausdrücklich nicht tun

- keinen vollständigen HiGodot-Refactor in unser Projekt kopieren
- nicht HiGodots Python-Server und unseren Godot-internen Host ungeprüft vermischen
- nicht den Goal Player durch starre HiGodot-Tests ersetzen
- nicht OCR als autoritative Quelle gegenüber SceneTree/GameState behandeln
- nicht jeden Script-Write mit einem globalen Filesystem-Scan verlangsamen
- nicht lange Testläufe in synchrone Edit-Batches packen
- nicht mutierende Tools ohne Hash, Diagnostics und Rollback anbieten

## 7. Priorisierte Implementationsschritte

### Schritt 1 — Editing-Referenzen prüfen und eigenen Grundstock implementieren

Nach bestandenem Adaptions-Gate als eigene, Godot-native Verträge implementieren:

- Script read/create/patch
- Filesystem read/write/search
- per-file GDScript-Diagnostics
- UID-/Scan-Hinweise
- sichere `res://`-Pfadvalidierung

### Schritt 2 — Transaction/Batch

- mehrere Editoränderungen atomar ausführen
- Stop-on-first-error
- Rollback-Receipt
- deferred Runtime/Test-Operationen ablehnen oder separat planen

### Schritt 3 — Testadapter

- HiGodot-artiges Suite-/Test-Result-Format für unsere Preflight- und MCP-Szenarien
- partial results, Timeout, load errors und Cursor
- keine Ablösung der bestehenden Constraints

### Schritt 4 — Chain Controller

- deklarative Chain-Schritte
- Abhängigkeiten und Preconditions
- headless/visible-Modus
- Savepoints und Retry

### Schritt 5 — Repair Loop

- Baseline-Diff
- Fehlerklassifikation
- Patch
- exakte Reproduktion
- betroffene Regressionen
- Evidence-Archivierung

## 8. Commit-History und Entwickler-Notes: Was ist tatsächlich bewährt?

Die Historie wurde lokal im separaten Clone geprüft. Sie ist kein Beweis dafür, dass jede Lösung fehlerfrei ist; sie zeigt aber, welche Probleme HiGodot wiederholt reproduziert, testet und in Verträge überführt hat.

### 8.1 Verifizierter Entwicklungsstand

- geprüfter HEAD: `03e74dc`, Tag `v3.2.0`, Datum 2026-08-25
- lokaler Clone: `C:/Users/Vannon/Documents/HiGodot-Research/godot-ai`
- Git-Tags im Clone: `100`
- ältester sichtbarer Tag: `v0.2.0`
- letzter sichtbarer Tag: `v3.2.0`
- Commits im Clone: `719`
- die jüngere Historie enthält viele Stabilitäts-, Test-, CI-, Transport-, Registry- und Diagnoseänderungen; sie ist nicht nur eine Folge von Authoring-Features

Die Releasefolge ist besonders dicht: von `v3.0.0` am 2026-07-13 bis `v3.2.0` am 2026-08-25 wurden zahlreiche Zwischenversionen veröffentlicht. Das belegt aktive Iteration und Releasepflege, aber nicht automatisch Fehlerfreiheit oder vollständige Übertragbarkeit in unser Prozessmodell.

### 8.2 Entwicklerregeln als Prüfkriterien für unser Tooling

Aus `AGENTS.md`, `docs/plugin-architecture.md`, `docs/testing-strategy.md`, `docs/testing.md`, `docs/implementation-plan.md` und `docs/friction-log.md` sind folgende Regeln als Prüf- und Qualitätskriterien erkennbar. Sie werden nicht automatisch als Implementierung übernommen:

1. **Python orchestriert, Godot mutiert.** Der MCP-Server übernimmt Transport, Session, Tool-Verträge und Orchestrierung; das Plugin führt Godot-Editoraktionen auf dem Main Thread aus.
2. **Readiness ist ein eigener Vertrag.** Schreiboperationen werden vor der Ausführung gated; `EDITOR_NOT_READY` bleibt ein stabiler Top-Level-Code mit konkreten Sub-Codes.
3. **Pfad- und Sicherheitsgrenzen sind zentral.** Schreibpfade werden validiert und auf das Projekt begrenzt; Loopback ist Teil der Sicherheitsgrenze.
4. **Jede Mutation meldet ihre Reversibilität.** Undo-fähige Editoraktionen tragen `undoable=true`; direkte Dateischreibvorgänge melden ausdrücklich, dass sie nicht über Editor-Undo rückgängig gemacht werden können.
5. **Toolflächen werden kompakt und suchbar gehalten.** Häufige Verben bleiben direkt erreichbar; seltene Verben liegen in Domain-Rollups; Ressourcen übernehmen read-heavy Zugriffe.
6. **Tests müssen echte Fehler sichtbar machen.** Zero-Assertion-Erkennung, `load_errors`, gespeicherte `failures[]`, Readback-Prüfungen und fail-closed CI verhindern grüne Scheinresultate.
7. **Lange Läufe müssen Transport und Teilergebnisse berücksichtigen.** `test_run` serviced den Transport zwischen Phasen, besitzt ein Budget und liefert Partial Results; lange Tests bleiben trotzdem eine bekannte Grenze.
8. **Live-Smoke ist neben Headless-Tests erforderlich.** Editor-API, Renderer, Game-Process, Self-Update und Port-/Ownership-Verhalten werden nicht allein durch Unit-Tests abgedeckt.

### 8.3 Historisch bestätigte Problemklassen

Die Commit-History und Friction-Logs zeigen wiederkehrende Problemklassen, die für unsere autonome Chain direkt relevant sind:

- **Import-Race:** `script_create` konnte erfolgreich schreiben, während ein direkt folgendes Attach die neue Ressource noch nicht sah. HiGodot führte dafür eine begrenzte, frameweise Import-Settle-Phase und ein explizites `import_settled`-Signal ein.
- **Unvollständige Diagnostik:** GDScript-Schreibfehler wurden zunächst nicht exakt genug an den Agenten zurückgegeben. Danach wurden Logger-basierte Write-Diagnostics und Tests eingeführt, die Validierungsläufe nicht in die normalen Editorlogs verschmutzen lassen.
- **Batch-Grenzen:** `batch_execute` wurde mit Vorvalidierung, Stop-on-first-error und Undo-Rollback gebaut. Später wurde ausdrücklich verhindert, dass lang laufende Tests innerhalb eines synchronen Batches Transport-Starvation verursachen.
- **Transport-Starvation:** Ein langer synchroner `test_run`-Lauf konnte die WebSocket-Keepalive-Verbindung verlieren. Die Lösung war kooperatives Servicing zwischen Testphasen, ein serverseitiges Budget, Abort-Zustände und abrufbare Partial Results.
- **Stille Testfehler:** Die CI wurde gegen leere oder nur teilweise entdeckte Suiten gehärtet; ungültige Suite-Namen liefern einen Fehler statt eines irreführenden `total=0`.
- **Reload-/Ownership-Risiken:** Die History enthält mehrere Korrekturen für Plugin-Reload, stale Server, PID-Reuse, Self-Update-Snapshots und gemischte Plugin-Zustände. `class_name`-Kompatibilität und `.uid`-Sidecars werden als Release-/Reload-Verträge behandelt.
- **Tool-Registry-Lebenszyklus:** Die aktuelle Custom-Tool-Registry validiert Batches vor Mutation, ersetzt Hot-Reloads anhand der Source-Identität, begrenzt Tool-Promotion und meldet Katalogänderungen kontrolliert an den Server.
- **Vision-/Client-Routing:** Vision-Routing wurde als eigene Schicht ergänzt, damit text-only Clients Screenshots über externe Vision APIs verwenden können. Das ist ein Adapterpfad, nicht die Behauptung, dass jeder Agent ein eigenes Vision-Modell besitzt.

### 8.4 Strikter Adaptions-Gate

Für unser Projekt gilt ab jetzt:

> **Ein HiGodot-Commit, eine vorhandene Funktion oder eine grüne Dokumentationsaussage ist allein kein Beweis, dass wir sie übernehmen dürfen.**

Ein Baustein wird erst als **zur Adaption zugelassen** markiert, wenn alle vier Nachweise vorliegen:

1. **Code-Nachweis:** Die aktuelle Implementierung und ihre Grenzen sind gelesen und verstanden.
2. **Automatischer Nachweis:** Ein reproduzierbarer Test deckt Erfolg, Fehlerfall und relevante Grenzfälle ab.
3. **Fehler-Nachweis:** Der ursprüngliche Fehler wurde als roter Test reproduziert oder die Ursache ist durch einen überprüfbaren Contract-Test belegt.
4. **Live-Nachweis:** Der Pfad läuft in einer isolierten Godot-Testinstanz auf dem unterstützten Engine-/Projektsetup; bei sichtbaren Funktionen zusätzlich mit echtem Renderer.

Die Nachweise müssen auf **unserer** Architektur wiederholt werden. Ein HiGodot-Test ist Referenzbeleg, aber kein Übertragungsbeleg.

### 8.5 Aktuelle Klassifikation der untersuchten Muster

| Muster | Aktueller Status | Konsequenz |
|---|---|---|
| erwartungsgebundener `script_patch` | Referenzkandidat; Code/Vertrag belegt, lokaler SnipWar-PoC noch offen | nicht als fertig behaupten; zuerst Hash-, Ambiguitäts- und Konflikttests |
| `res://`-Pfadvalidierung | Referenzkandidat; HiGodot-Code/Tests dokumentiert | eigene zentrale Validator-Implementierung mit Traversal-Tests |
| per-file GDScript-Diagnostics | Referenzkandidat; Historie und Code belegt | eigener Diagnostic-Receipt, kein stiller Fallback bei unvollständigen Daten |
| Import-/Resource-Settlement | Referenzkandidat; Race und begrenzte Lösung belegt | eigener Readiness-Barrier-Contract statt fixer Wartezeit |
| `batch_execute` mit Editor-Undo | Referenzkandidat; Code und Rollback-Vertrag belegt | nur für Editoraktionen; Dateischreiben erhält eigenes Journal |
| Test-Budget, Servicing, Partial Results | HiGodot-seitig stark belegt, Transfer offen | eigener asynchroner Chain-Runner mit explizitem Jobzustand |
| Liveness-Receipt | Referenzkandidat; Tool-/Dokumentationsvertrag belegt | mit unserem Runtime-Host und Goal Player separat verifizieren |
| Custom-Tool-Registry mit Atomic Registration | Code/Commit belegt, Live- und Cross-Reload-Nachweis offen | Designprinzip übernehmen, Lifecycle-Test zuerst |
| Vision-Routing | für HiGodot belegt, für unser OCR-Ziel nicht gleichwertig | nicht als Editing-Baustein übernehmen |

**Keine Zeile mit Status „Referenzkandidat“ darf in die Implementierung als „bereits bewährt“ eingehen.** Sie ist nur ein priorisierter Prüfauftrag.

### 8.6 Eigene, stabile Ersatzverträge statt HiGodot-Workarounds

Wir übernehmen nicht die interne Notlösung, sondern definieren das Problem sauber:

| Historischer Workaround | Eigenes natives Tooling für unser MCP |
|---|---|
| Nach `script_create` auf `ResourceLoader.exists()` pollen | `ProjectResourceBarrier`: wartet auf ein konkretes Resource-/Filesystem-Event, besitzt Deadline, Generation und eindeutigen Receipt |
| Editor-Undo als Batch-Rollback | `WorkspaceJournal`: Vorher-Hash, Patch/Preimage, Nachher-Hash, Transaktions-ID und explizites Rollback für Dateien; Undo bleibt nur für Editorobjekte |
| Transport zwischen Testphasen notdürftig bedienen | `JobScheduler`: kooperative Yield-Punkte, bounded mailbox, Busy-Zustand, Abort und Partial-Result-Store als eigener Jobvertrag |
| globalen Filesystem-Scan als Sicherheitsnetz verwenden | inkrementelles Index-Invalidieren plus explizite `scan_barrier`-Operation nur bei neuen Klassen/Resources |
| fehlende Loggerdetails durch unpräzise Fallbacks ersetzen | strukturierter Diagnostic-Status `complete/partial/unavailable`; unvollständige Diagnostik wird nie als fehlerfrei gemeldet |
| Response-Menge über ad-hoc Feldfilter reduzieren | schema-first Envelope mit Größenbudget, Artefakt-Referenzen, deterministischer Sortierung und explizitem `truncated` |
| Reload-Probleme durch Reihenfolge-Workarounds kaschieren | Lifecycle-Generationen, Besitznachweis, invalidierte Handles und einheitliches Teardown-Protokoll |

Das Ziel ist damit nicht „HiGodot nachbauen“, sondern aus jedem bestätigten Problem einen stabileren, expliziten Vertrag zu machen.

### 8.7 Was erst nach dem Gate adaptiert werden darf

Diese Muster sind unabhängig von HiGodots konkreter Python/FastMCP-Architektur sinnvoll, aber bis zum lokalen Nachweis nur Kandidaten:

- erwartungsgebundene Patches mit `before_hash` oder eindeutigem `old_text`
- zentrale `res://`-Pfadvalidierung vor jedem Write
- per-file Write-Diagnostics
- begrenzte Resource-Readiness-Barriers
- Trennung von synchronen Editor-Batches und deferred Runtime-/Testläufen
- Stop-on-first-error mit Rollback-Receipt
- Testresultate mit `passed`, `failed`, `skipped`, `load_errors`, `failures`, `duration_ms`, `aborted` und Partial Results
- Busy-/Readiness-Zustände mit retrybaren Fehlern
- Tool-Metadaten und Response-Filter für read/write, headless/visible und sync/async
- Lifecycle-/Reload-Aufräumregeln mit Generation und Besitznachweis

### 8.8 Was wir nicht als fertige Lösung übernehmen dürfen

- HiGodots Python/FastMCP-Server nicht ungeprüft in unseren Godot-internen TCP/stdio-Host kopieren.
- Editor-Undo nicht als Ersatz für Dateisystem-Rollback behandeln; `script_create`/`filesystem_write_text` benötigen separate Savepoints oder Workspace-Snapshots.
- `batch_execute` nicht als Chain-Orchestrator missverstehen; lange Tests, sichtbares Gameplay, OCR und Repair-Schleifen brauchen eigene asynchrone Schritte.
- `test_run` nicht als Gameplay-Test betrachten; es prüft GDScript-Suites und muss mit `Preflight`, `McpGoalPlayer` und Visible Evidence verbunden werden.
- Import-Settle nicht als unendliches Warten implementieren; HiGodots eigener Vertrag ist begrenzt und meldet den Timeoutzustand.
- Release-/Reload-Kompatibilitätsregeln nicht auf unsere Scripts übertragen, ohne unsere `class_name`, UID- und Headless-Preflight-Konventionen zu prüfen.
- historische Friction-Fixes nicht als Beweis behandeln, dass ein Pfad heute noch fehlerfrei ist; jede Adaption braucht einen kleinen roten Test und einen Live-Smoke.

### 8.9 Konsequenz für unsere Implementierung

Die History verändert die Implementationsrichtung nicht, sie schärft sie:

```text
HiGodot-Problemverträge und Schnittstellen prüfen
→ red tests für Import, Diagnostics, Rollback, Timeout und Partial Results
→ eigene Godot-native Implementierung in unsere bestehenden Schichten
→ Registry/Response-Filtering anbinden
→ Headless-Preflight und McpTestRunner verbinden
→ GoalPlayer + Freeze/Step + UX/OCR als sichtbare Schritte einreihen
→ gemeinsames Evidence-Receipt schreiben
```

Der wichtigste Lerneffekt aus HiGodot ist daher nicht ein einzelner Handler. Es ist die Entwicklungsmethode: Jede neue Agentenfähigkeit wird mit einem maschinenlesbaren Vertrag, einem reproduzierbaren Fehlerfall, einer passenden Teststufe und einem Live-Smoke abgesichert.

## 9. Ergebnis

**Was können wir schon?** Runtime-Gameplay, Freeze/Step, UX, Vision/OCR, Goal Player, E2E, Preflight und Archivierung.

**Was können wir als Nächstes prüfen?** HiGodots Script-/Filesystem-Editing, Diagnostics, Batch-Rollback, Liveness, Test-Resultate, Cursor/Pagination und Resource-Verträge. Eine Adaption ist erst nach dem lokalen Adaptions-Gate erlaubt.

**Wo passt es hin?** Als neue Project/Edit-/Validation-Schicht oberhalb bzw. neben Registry und Lifecycle, vor den bestehenden Goal-/UX-/Vision-/Preflight-Schichten.

**Wie arbeitet es zusammen?** Editing erzeugt eine validierte Projektversion; Headless-Tests prüfen Logik; Goal Player und Visible Runtime prüfen Spielerfahrung; Vision/OCR liefert Evidenz; Archive speichert den gesamten Lauf.

**Was ist die eigentliche Optimierung?** Nicht mehr Einzeltools, sondern ein gemeinsamer Agenten-Run mit stabilen Hashes, Diagnostics, Preconditions, Checkpoints, Rollback und reproduzierbarer Chain.

Das ist eine Implementationsrichtung, kein Refactor-Vorschlag.
