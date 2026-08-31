# Branch-Audit 2026-08-30

## Remote-Branches (GitHub)
| Branch | SHA | Status |
|--------|-----|--------|
| `origin/main` | 41aafa3 | ✅ Aktiv, HEAD |

## Lokale Worktree-Branches (verwaist)
Alle zeigen auf denselben Commit wie `main` (41aafa3 – "Echo erinnert: Sandbox-Determinismus korrigieren").

| Branch | SHA | Aktion |
|--------|-----|--------|
| `agentgate/buffy` | 41aafa3 | → löschen |
| `worktree-wf_84048bc6-e5e-2` | 41aafa3 | → löschen |
| `worktree-wf_84048bc6-e5e-3` | 41aafa3 | → löschen |
| `worktree-wf_84048bc6-e5e-9` | 41aafa3 | → löschen |
| `worktree-wf_f8728f5f-5ef-1` | 41aafa3 | → löschen |
| `worktree-wf_f8728f5f-5ef-2` | 41aafa3 | → löschen |
| `worktree-wf_f8728f5f-5ef-3` | 41aafa3 | → löschen |
| `worktree-wf_f8728f5f-5ef-10` | 41aafa3 | → löschen |

## Fazit
- **0** "Delete"-Branches auf GitHub gefunden (nur `main` existiert remote).
- **8** verwaiste lokale Worktree-Branches identifiziert, alle HEAD-gleich.
- Keine verlorenen Commits – alles sicher in `main`.

## Durchgeführte Bereinigung

**Worktrees entfernt (7 Stück):**
- `.agent-worktrees/agentgate`
- `.claude/worktrees/wf_84048bc6-e5e-{2,3,9}`
- `.claude/worktrees/wf_f8728f5f-5ef-{1,2,3}`

**Branches gelöscht (8 Stück):**
- `agentgate/buffy`
- `worktree-wf_84048bc6-e5e-{2,3,9}`
- `worktree-wf_f8728f5f-5ef-{1,2,3,10}`

**Ergebnis:** Nur noch `main` lokal + remote. Sauber.
