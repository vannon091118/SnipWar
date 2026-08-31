# AgentGate

AgentGate schützt Datei-Zuständigkeiten zwischen parallelen Agenten. Es schreibt nur nach `.git/agent-activity/` (Fallback `.agent-activity/`, beide ignoriert) und liest den Git-Zustand.

## Check-In

```bash
export AGENT_NAME=buffy
bash scripts/agent_activity.sh check-in --agent buffy --task "AgentGate umsetzen" --scope-from-staged
```

Ein aktiver Fremd-Lock blockiert den Check-In mit Exit 2. `--level` ist absichtlich nicht zulässig; die Verifikationsstufe wird deterministisch aus den Dateien abgeleitet.

Weitere Befehle:

```bash
# Ältesten stale/NO-OUT-Check-In übernehmen; Dateien und Task werden synchronisiert.
bash scripts/agent_activity.sh takeover <alter-agent> "reason für die Übernahme"
# Vorher: neuer Agent muss aktiv eingecheckt sein; ACTIVE-Kollisionen blockieren.
```

`takeover` ist nur für stale/NO-OUT-Einträge zulässig und setzt einen aktiven Check-In des übernehmenden Agenten voraus. Der Übernahmebeleg wird ausschließlich im AgentGate-Zustand journalisiert (`from`, `to`, `reason`, `files`) und als Registry-Felder am aktiven Agenten gespeichert.

```bash
bash scripts/agent_activity.sh update --files path/to/file --reason "kausaler Fix / F-123"
bash scripts/agent_activity.sh heartbeat
bash scripts/agent_activity.sh status
bash scripts/agent_activity.sh check path/to/file
bash scripts/agent_activity.sh check-out
```

## Gate

Der Pre-Commit-Hook ruft `run-preflight` auf. Es blockiert, wenn die committende Identität keinen Check-In besitzt, eine staged Datei ungedeckt ist oder ein aktiver Fremd-Lock kollidiert. Auto-managed Dateien (`*.uid`, `*.import`, DOKI-Artefakte) sind abgedeckt. Stale Locks werden nur als `STALE` gemeldet und nicht automatisch entfernt.

Ungedeckte oder abgestürzte Arbeit wird einzeln auditiert:

```bash
bash scripts/agent_activity.sh recheck-in --audit \
  --files path/to/file --file-reason "path/to/file:legacy work" --as legacy
```

`prune` archiviert stale Registry-Einträge; `prune --force` entfernt den aktiven Eintrag nach Archivierung. `--purge` löscht den Eintrag endgültig und ist nur für bewusst bereinigte Zustände gedacht.

## DOKI-Identitäts-Seed

`--scope-from-staged` leitet die Coverage ausschließlich aus `git diff --cached --name-only` ab und verhindert manuelle Scope-Drift.

Jeder Check-In erzeugt einmalig den stabilen Seed `agent:<name>:<host>:<pid>:<in>`. Updates behalten diesen Seed. `bash scripts/agent_activity.sh seed <name>` gibt ihn für den aktiven DOKI-Flow aus. Vor `doki prepare` wird er als `AGENT_ACTIVITY_SEED` exportiert; `prepare_flow.gd` erzeugt daraus den Owner-Token `agent:<name>:seed:<seed>`. Ein gesetzter, fehlender oder abweichender Seed blockiert das Gate fail-closed. Der Seed ist eine Identitätsbindung, kein kryptografischer Beweis.

## NO-OUT-Zeitregel

Ein Check-In ist höchstens zwei Stunden aktiv. Nach einer Stunde ist ein verpflichtender Re-Check nötig; `recheck-in --audit` muss jede Datei mit `--file-reason` und einem journalisierten `from`, `to`, `reason` und `file` bestätigen. Nach zwei Stunden wird der Eintrag `NO-OUT`: Er blockiert keine weiteren Gates dauerhaft, gilt aber nicht mehr als aktiver Check-In und muss neu eingecheckt werden. Die Zustandswerte sind in `status --all` sichtbar; die Grenzwerte können für Tests über `AGENT_ACTIVITY_RECHECK_TTL` und `AGENT_ACTIVITY_MAX_TTL` gesetzt werden.

## Zustandsmodell

Je Agent existieren Registry, `.files`, Exception- und Audit-Protokolle. `journal.log` ist append-only. Heartbeats älter als `AGENT_ACTIVITY_TTL` (Default 2700 Sekunden) erscheinen als `STALE`. Bei Branch-Mismatch schreibt das Gate eine WARN-Meldung und einen Journal-Eintrag, blockiert aber nicht. Transfers auf lokalen `main` verlangen einen aktiven Check-In, prüfen Quell-Datei-Locks vor dem Cherry-Pick, schreiben einen Transfer-Record und erhöhen `imports`; ein bereits importierter Quell-HEAD ist ein No-op. Unbekannte staged Dateien bleiben fail-closed. Innerhalb des aktiven Feature-Branch-Scope gelten alle vorhandenen Änderungen als dem Agent zugeordnet; es gibt dort keine Fremdänderungen.
