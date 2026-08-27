# Findings — Separation of Concerns & Repository-Hygiene

## Baseline
- Branch `main`, lokal 1 Commit vor `origin/main`.
- Letzter Commit: `257d683 feat: decouple MCP bridge from project-specific assumptions`.

## Adversariale Review

### Bestätigte Lücke
`McpPlaythroughTools._state_fingerprint()` rief einen nicht vorhandenen `_get_project_adapter()` auf. Der Codepfad wurde bei normalem Start nicht zwingend berührt, war aber beim State-Fingerprint eines Playthroughs zur Laufzeit fehleranfällig.

**Behebung:** Gemeinsame projektagnostische Adapter-Auflösung ergänzt: konfigurierter absoluter NodePath, danach konventioneller Adaptername.

### Geprüfte Pfade
- Adapter-, State-, EventLog-, PlanetField- und WorkerManager-Auflösung
- relative/ungültige konfigurierte NodePaths
- fehlende Nodes und fehlende Methoden
- Registry-Routing und Async-Dispatch
- Playthrough-State-Fingerprint
- Chain-Expression-Kontext
- E2E-Pause-Menü- und Node-Erkennung
- keine neuen temporären oder historischen Artefakte gelöscht

### Nicht behobene Out-of-Scope-Befunde
- Historische SnipWar-Texte in Client-Playthroughs/Reports
- Headless-MCP-Szenariotest ohne sichtbaren Renderer
- bekannte Preflight-Isolation-/Resource-Leak-Warnungen

## Verifikation
- MCP Build Check: bestanden
- Godot Preflight: 39/39 Constraints, 2020/2020 Assertions, `RESULT: PASSED`
