#!/usr/bin/env bash
set -euo pipefail

# ─── DOKI Auto-Push-Wrapper ────────────────────────────────────────────────
# Kontrollierter Einstiegspunkt fuer den echten DOKI-Hauptcommit + Push.
# Der Agent fuehrt ZUERST `doki prepare`, schreibt den Body und fuehrt
# `doki finish` aus. Dieser Wrapper uebernimmt dann:
#   1. Pre-Checks (Rebase/Merge/Seed/Dirty/Mutex)
#   2. git commit -F .commit_msg.txt
#   3. doki finalize
#   4. Transport-Commit (staged auto-managed Artefakte)
#   5. Push-Pending-Marker
#   6. git push
#   7. Cleanup (Marker + Mutex)
#
# Exit-Codes:
#   0  = PUSH_OK
#   10 = COMMIT_FAILED
#   11 = FINALIZE_FAILED
#   12 = DIRTY_BLOCKED
#   13 = MUTEX_BUSY
#   20 = PUSH_FAILED
# ──────────────────────────────────────────────────────────────────────────

# ── Skript-Lage ───────────────────────────────────────────────────────────
_SRC="${BASH_SOURCE[0]:-$0}"
if [[ "$_SRC" != */* ]]; then
    _FOUND="$(command -v "$_SRC" 2>/dev/null || true)"
    [ -n "$_FOUND" ] && _SRC="$_FOUND"
fi
SCRIPT_DIR="$(cd "$(dirname "$_SRC")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

# ── Konstanten ────────────────────────────────────────────────────────────
LOCK_DIR=".git/doki-push.lock"
PENDING_MARKER=".doki/push_pending.json"
AUTO_MANAGED=( \
    ".doki/narrative_chain.json" \
    ".doki/change_index.json" \
    "CHANGELOG.md" \
    "scripts/doki/data/arcs.json" \
    ".commit_msg.txt" \
)
# .commit_msg.txt wird von finish_flow gestaged — muss im Dirty-Check
# toleriert werden, darf aber NICHT im Transport-Commit landen.
TRANSPORT_FILES=( \
    ".doki/narrative_chain.json" \
    ".doki/change_index.json" \
    "CHANGELOG.md" \
    "scripts/doki/data/arcs.json" \
)
LOCK_TTL_SEC=300  # 5 Minuten — danach gilt Mutex als stale

# ── Exit-Hilfen ────────────────────────────────────────────────────────────
COMMIT_FAILED=10
FINALIZE_FAILED=11
DIRTY_BLOCKED=12
MUTEX_BUSY=13
PUSH_FAILED=20

die() { echo "ERROR: $*" >&2; }

cleanup_mutex() { rm -rf "$LOCK_DIR" 2>/dev/null || true; }

# Trap fuer SIGINT/SIGTERM — Mutex immer freigeben
trap 'cleanup_mutex; echo "SIGNAL: Interrupted — Mutex freigegeben." >&2; exit 130' INT TERM

# ── Godot-Hilfe ────────────────────────────────────────────────────────────
if [ -z "${GODOT_BIN:-}" ] || [ ! -x "${GODOT_BIN}" ]; then
    die "GODOT_BIN nicht gesetzt oder nicht ausfuehrbar."
    exit $COMMIT_FAILED
fi
run_godot() {
    local script="$1"; shift
    "$GODOT_BIN" --headless --path . --script "$script" "$@"
}

# ═══════════════════════════════════════════════════════════════════════════
# 1. PRE-CHECKS
# ═══════════════════════════════════════════════════════════════════════════
echo "=== doki-commit: Pre-Checks ==="

# 1a. Rebase / Merge — hart blockieren
git_dir="$(git rev-parse --git-dir 2>/dev/null || echo '.git')"
if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ]; then
    die "Rebase aktiv — kein Auto-Push waehrend Rebase."
    cleanup_mutex
    exit $COMMIT_FAILED
fi
if [ -f "$git_dir/MERGE_HEAD" ]; then
    die "Merge aktiv — kein Auto-Push waehrend Merge."
    cleanup_mutex
    exit $COMMIT_FAILED
fi

# 1b. AgentGate-Seed
if [ -z "${AGENT_NAME:-}" ] || [ -z "${AGENT_ACTIVITY_SEED:-}" ]; then
    die "AGENT_NAME oder AGENT_ACTIVITY_SEED nicht gesetzt."
    exit $COMMIT_FAILED
fi

# 1c. .commit_msg.txt muss existieren
if [ ! -f ".commit_msg.txt" ]; then
    die ".commit_msg.txt fehlt — doki finish wurde nicht ausgefuehrt."
    exit $COMMIT_FAILED
fi

# 1d. Push-Mutex erwerben (atomar via mkdir)
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
head_hash=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

# Detached HEAD — kein Auto-Push
if [ "$branch" = "HEAD" ]; then
    die "Detached HEAD — kein Auto-Push ohne Branch."
    exit $COMMIT_FAILED
fi

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    # Mutex existiert — stale?
    lock_pid=0
    lock_time=0
    [ -f "$LOCK_DIR/pid" ] && lock_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo 0)
    [ -f "$LOCK_DIR/timestamp" ] && lock_time=$(cat "$LOCK_DIR/timestamp" 2>/dev/null || echo 0)
    now=$(date +%s)
    age=$((now - lock_time))
    if [ "$age" -lt "$LOCK_TTL_SEC" ] && [ "$lock_pid" -gt 0 ] && kill -0 "$lock_pid" 2>/dev/null; then
        die "Push-Mutex belegt (PID $lock_pid, Age ${age}s)."
        exit $MUTEX_BUSY
    fi
    echo "WARN: Stale Mutex erkannt (PID $lock_pid, Age ${age}s) — uebernehme." >&2
    rm -rf "$LOCK_DIR"
    # Retry-Loop (max 3 Versuche, 1s Interval)
    mutex_acquired=0
    for _retry in 1 2 3; do
        if mkdir "$LOCK_DIR" 2>/dev/null; then mutex_acquired=1; break; fi
        sleep 1
    done
    if [ "$mutex_acquired" -eq 0 ]; then
        die "Mutex-Erwerb fehlgeschlagen nach 3 Versuchen."
        exit $MUTEX_BUSY
    fi
fi

echo $$ > "$LOCK_DIR/pid"
echo "$branch" > "$LOCK_DIR/branch"
echo "$head_hash" > "$LOCK_DIR/head"
echo "$(date +%s)" > "$LOCK_DIR/timestamp"
echo "${AGENT_NAME}" > "$LOCK_DIR/agent"
echo "${AGENT_ACTIVITY_SEED}" > "$LOCK_DIR/seed"

# 1e. Dirty-State: keine uncommitted non-auto-managed Aenderungen
has_dirty=0
dirty_list=""

_is_auto() {
    local f="$1"
    for am in "${AUTO_MANAGED[@]}"; do
        if [ "$f" = "$am" ]; then
            return 0
        fi
    done
    return 1
}

# Staged Dateien, die NICHT zu auto-managed gehoeren
while IFS= read -r f; do
    [ -z "$f" ] && continue
    if ! _is_auto "$f"; then
        dirty_list="${dirty_list}  staged: $f\n"
        has_dirty=1
    fi
done < <(git diff --cached --name-only 2>/dev/null) || { die "git diff fehlgeschlagen."; cleanup_mutex; exit $COMMIT_FAILED; }

# Unstaged Aenderungen
while IFS= read -r f; do
    [ -z "$f" ] && continue
    if ! _is_auto "$f"; then
        dirty_list="${dirty_list}  unstaged: $f\n"
        has_dirty=1
    fi
done < <(git diff --name-only 2>/dev/null) || { die "git diff fehlgeschlagen."; cleanup_mutex; exit $COMMIT_FAILED; }

# Nicht-ignorierte untracked Dateien (auto-managed tolerieren fuer Erstlauf)
while IFS= read -r f; do
    [ -z "$f" ] && continue
    if ! _is_auto "$f"; then
        dirty_list="${dirty_list}  untracked: $f\n"
        has_dirty=1
    fi
done < <(git ls-files --others --exclude-standard 2>/dev/null)

if [ "$has_dirty" -eq 1 ]; then
    die "Dirty-State blockiert Push:"
    printf '%b' "$dirty_list"
    cleanup_mutex
    exit $DIRTY_BLOCKED
fi

echo "  Pre-Checks: OK (Branch=$branch, Seed=$AGENT_ACTIVITY_SEED)"

# ═══════════════════════════════════════════════════════════════════════════
# 2. COMMIT
# ═══════════════════════════════════════════════════════════════════════════
echo "=== doki-commit: git commit ==="

# Wrapper aktiv setzen — post-commit Hook ueberspringt finalize
# Inline: nur fuer diesen git commit, nicht global exportiert
if ! DOKI_WRAPPER_ACTIVE=1 git commit -F .commit_msg.txt; then
    die "git commit fehlgeschlagen."
    cleanup_mutex
    exit $COMMIT_FAILED
fi

commit_hash=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
echo "  Commit: $commit_hash"

# ═══════════════════════════════════════════════════════════════════════════
# 3. FINALIZE
# ═══════════════════════════════════════════════════════════════════════════
echo "=== doki-commit: doki finalize ==="

if ! run_godot "res://scripts/doki/doki.gd" -- finalize; then
    die "doki finalize fehlgeschlagen (lokaler Commit existiert)."
    cleanup_mutex
    exit $FINALIZE_FAILED
fi

echo "  Finalize: OK"

# ═══════════════════════════════════════════════════════════════════════════
# 4. TRANSPORT-COMMIT (auto-managed Artefakte fuer Remote)
# ═══════════════════════════════════════════════════════════════════════════
echo "=== doki-commit: Transport-Commit ==="

# Transport-Dateien stagen (NUR finalize-Artefakte, NICHT .commit_msg.txt)
transport_files=()
for am in "${TRANSPORT_FILES[@]}"; do
    if [ -f "$am" ]; then
        transport_files+=("$am")
    fi
done

if [ ${#transport_files[@]} -gt 0 ]; then
    has_transport=0
    for tf in "${transport_files[@]}"; do
        if ! git diff --quiet HEAD -- "$tf" 2>/dev/null; then
            has_transport=1
            break
        fi
    done

    if [ "$has_transport" -eq 1 ]; then
        if ! git add "${transport_files[@]}" 2>/dev/null; then
            die "git add fuer Transport-Commit fehlgeschlagen."
            cleanup_mutex
            exit $FINALIZE_FAILED
        fi
        if ! git diff --cached --quiet 2>/dev/null; then
            if echo "DOKI finalize Artefakte" | git commit -F - 2>/dev/null; then
                echo "  Transport-Commit: $(git rev-parse --short HEAD 2>/dev/null || echo 'OK')"
            else
                die "Transport-Commit fehlgeschlagen."
                cleanup_mutex
                exit $FINALIZE_FAILED
            fi
        else
            echo "  Transport-Commit: keine Aenderungen (nur index)"
        fi
    else
        echo "  Transport-Commit: keine Aenderungen"
    fi
else
    echo "  Transport-Commit: keine auto-managed Dateien vorhanden"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 5. POST-FINALIZE DIRTY-STATE
# ═══════════════════════════════════════════════════════════════════════════
echo "=== doki-commit: Post-Finalize Dirty-State ==="

post_dirty=0
post_dirty_list=""

# Staged — alle auto-managed sind erlaubt
while IFS= read -r f; do
    [ -z "$f" ] && continue
    if ! _is_auto "$f"; then
        post_dirty_list="${post_dirty_list}  staged: $f\n"
        post_dirty=1
    fi
done < <(git diff --cached --name-only 2>/dev/null) || true

# Unstaged — auto-managed duerfen geaendert sein (finalize hat sie geschrieben)
while IFS= read -r f; do
    [ -z "$f" ] && continue
    if ! _is_auto "$f"; then
        post_dirty_list="${post_dirty_list}  unstaged: $f\n"
        post_dirty=1
    fi
done < <(git diff --name-only 2>/dev/null) || true

# Untracked — auto-managed tolerieren
while IFS= read -r f; do
    [ -z "$f" ] && continue
    if ! _is_auto "$f"; then
        post_dirty_list="${post_dirty_list}  untracked: $f\n"
        post_dirty=1
    fi
done < <(git ls-files --others --exclude-standard 2>/dev/null)

if [ "$post_dirty" -eq 1 ]; then
    die "Post-Finalize Dirty-State: unerwartete Dateien:"
    printf '%b' "$post_dirty_list"
    cleanup_mutex
    exit $DIRTY_BLOCKED
fi

echo "  Dirty-State: clean"

# ═══════════════════════════════════════════════════════════════════════════
# 6. PUSH-PENDING-MARKER (atomar vor Push)
# ═══════════════════════════════════════════════════════════════════════════
echo "=== doki-commit: Push-Pending-Marker ==="

mkdir -p .doki
cat > "$PENDING_MARKER.tmp" <<MARKEREOF
{
    "status": "pending",
    "commit": "$commit_hash",
    "branch": "$branch",
    "agent": "${AGENT_NAME}",
    "pid": $$,
    "timestamp": $(date +%s),
    "pre_push": true
}
MARKEREOF
mv -f "$PENDING_MARKER.tmp" "$PENDING_MARKER"
echo "  Marker: $PENDING_MARKER (atomar geschrieben)"

# ═══════════════════════════════════════════════════════════════════════════
# 7. PUSH
# ═══════════════════════════════════════════════════════════════════════════
echo "=== doki-commit: git push origin $branch ==="

# Upstream-Check: wenn kein Upstream existiert, mit --set-upstream pushen
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || true)
if [ -z "$upstream" ]; then
    echo "  Kein Upstream — nutze --set-upstream"
    push_output=""
    push_rc=0
    push_output=$(git push --set-upstream origin "$branch" 2>&1) || push_rc=$?
else
    push_output=""
    push_rc=0
    push_output=$(git push origin "$branch" 2>&1) || push_rc=$?
fi

if [ "$push_rc" -ne 0 ]; then
    die "PUSH_FAILED (Exit $push_rc): $push_output"
    # Marker bleibt als Recovery-Hinweis
    cleanup_mutex
    echo ""
    echo "=== doki-commit: RESULT ==="
    echo "  Commit:   OK ($commit_hash)"
    echo "  Finalize: OK"
    echo "  Push:     FEHLGESCHLAGEN (Exit $push_rc)"
    echo ""
    echo "  Recovery: bei naechstem Lauf push erneut versuchen oder Marker manuell loeschen:"
    echo "    rm -f $PENDING_MARKER"
    exit $PUSH_FAILED
fi

echo "  Push: $push_output"

# ═══════════════════════════════════════════════════════════════════════════
# 8. CLEANUP
# ═══════════════════════════════════════════════════════════════════════════
echo "=== doki-commit: Cleanup ==="

rm -f "$PENDING_MARKER"
cleanup_mutex
echo "  Marker + Mutex: cleanup erledigt"

echo ""
echo "=== doki-commit: RESULT ==="
echo "  Commit:   OK ($commit_hash)"
echo "  Finalize: OK"
echo "  Push:     OK (origin/$branch)"
echo ""
exit 0
