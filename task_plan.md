# AgentGate Gesamtscope

## Ziel
AgentGate v3.2 einschließlich DOKI-Identitätsseed als ein vollständiger Slice.

## Status
- [x] AgentGate-Kernmodul mit Check-In, Update, Heartbeat, Check-Out, Gate, Audit, Prune und Transfer
- [x] Seed-Erzeugung beim Check-In und Seed-Match-Gate
- [x] DOKI-Owner-Token `agent:<name>:seed:<seed>` ohne PID-Fallback
- [x] Preflight-Constraint, Scanner, Force-Include und Hook
- [x] Dokumentation, AGENTS-Regel und Ignore-Fallback
- [x] Readiness-/Polish-Findings einschließlich Self-Test-Smokes
- [x] Shell-Syntax, Self-Test, Preflight-List und Compile-Gate
- [ ] Ein vollständiger DOKI-Bootstrap-Commit für den Gesamtscope

## Nachweis
- Keine echten TODO/FIXME-Marker in der AgentGate-Scheibe.
- Alle aktuellen Änderungen auf `feature/agentgate` gehören zum Auftragsscope.
- `owner.json` wird nicht manuell verändert; der Seed-Token wird durch `doki prepare` erzeugt.

## Nächster Schritt
Gesamten aktuellen Scope gezielt stagen, Seed exportieren, DOKI prepare/finish ausführen und genau einen lokalen Commit erzeugen.
