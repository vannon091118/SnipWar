# Fortschritt AgentGate

- Branch `feature/agentgate` ist aktiver Arbeitsbereich; bestehende Änderungen auf diesem Branch gehören zum Scope.
- A1 behoben: `run_gate` blockiert Rewind/Clobber per `git merge-base --is-ancestor`.
- A2 behoben: Severity wird numerisch über `max_level` abgeleitet, nicht alphabetisch sortiert.
- A3 behoben: Transfer verlangt Identität/Check-In und führt vor Cherry-Pick den vollständigen Gate-Pfad aus; Konflikte bleiben bei `transfer --continue` fortsetzbar.
- A4 behoben: Branch-Mismatch wird gewarnt und journalisiert.
- A5 erweitert: Self-Test deckt Check-In, Heartbeat, Update, Recheck-In und Status ab; Lock-/Drift-Prüfung läuft über Gate.
- A6 behoben: Constraint ist scanner-registriert; `preflight.gd --list` zeigt `agent_activity` als pure Constraint.
- A7 behoben: Transfer aktualisiert Registry-Feld `imports` und schreibt Transfer-Record.
- Verifiziert: `bash -n scripts/agent_activity.sh`, Self-Test, `git diff --check`, Godot Constraint-List.
- F4 geklärt: Alle Änderungen auf `feature/agentgate` gehören zum AgentGate-Scope; es gibt keine Fremdänderungen innerhalb dieses Branch-Scope.
