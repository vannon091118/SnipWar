#!/usr/bin/env bash
set -u
set -o pipefail

TTL="${AGENT_ACTIVITY_TTL:-2700}"
NO_OUT_RECHECK_SECONDS="${AGENT_ACTIVITY_RECHECK_TTL:-3600}"
NO_OUT_MAX_SECONDS="${AGENT_ACTIVITY_MAX_TTL:-7200}"

now() { date +%s 2>/dev/null || echo 0; }
die() { printf 'AGENTGATE ERROR: %s\n' "$1" >&2; exit "${2:-1}"; }
repo_root() { git rev-parse --show-toplevel 2>/dev/null || die "kein git-Repo" 3; }
state_dir() {
  if [ -n "${AGENT_ACTIVITY_DIR:-}" ]; then printf '%s\n' "$AGENT_ACTIVITY_DIR"; return; fi
  local root common; root=$(repo_root); common=$(git -C "$root" rev-parse --git-common-dir 2>/dev/null || true)
  [ -n "$common" ] || { printf '%s/.agent-activity\n' "$root"; return; }
  case "$common" in .git) printf '%s/.git/agent-activity\n' "$root";; /*) printf '%s/agent-activity\n' "$common";; *) printf '%s/%s/agent-activity\n' "$root" "$common";; esac
}
ensure_state() { local d; d=$(state_dir); mkdir -p "$d/agents" "$d/transfers" "$d/archive"; printf '%s\n' "$d"; }
journal() { local d; d=$(ensure_state); printf '%s|%s|%s|%s\n' "$(now)" "$1" "$2" "$3" >> "$d/journal.log"; }
agents_dir() { printf '%s/agents\n' "$(state_dir)"; }
reg_file() { printf '%s/%s\n' "$(agents_dir)" "$1"; }
files_file() { printf '%s/%s.files\n' "$(agents_dir)" "$1"; }
exc_file() { printf '%s/%s.exceptions\n' "$(agents_dir)" "$1"; }
audit_file() { printf '%s/%s.audit\n' "$(agents_dir)" "$1"; }
load_field() { awk -F= -v k="$2" 'index($0,k"=")==1{sub(/^[^=]*=/,"",$0);print;exit}' "$(reg_file "$1")" 2>/dev/null; }
set_field() { local f tmp; ensure_state >/dev/null; f=$(reg_file "$1"); tmp="$f.tmp.$$"; { [ -f "$f" ] && awk -F= -v k="$2" 'index($0,k"=")!=1 {print}' "$f" || true; printf '%s=%s\n' "$2" "$3"; } > "$tmp" && mv "$tmp" "$f"; }
list_agents() { local f; for f in "$(agents_dir)"/*; do [ -f "$f" ] || continue; case "$f" in *.files|*.exceptions|*.audit) continue;; esac; basename "$f"; done; }
resolve_identity() { [ -n "${AGENT_NAME:-}" ] && { printf '%s\n' "$AGENT_NAME"; return; }; die "AGENT_NAME fehlt — Agent-Name muss aus dem Check-In stammen" 2; }
seed_for() { local a=${1:-$(resolve_identity || true)}; [ -n "$a" ] || die "Agent-Identität fehlt" 2; local seed beat; seed=$(load_field "$a" seed || true); beat=$(load_field "$a" beat || echo 0); seed=${seed:-}; beat=${beat:-0}; [ -n "$seed" ] || die "kein Seed für Agent $a" 2; [ "$beat" -gt 0 ] || die "Check-In für Agent $a ist nicht aktiv" 2; printf '%s\n' "$seed"; }
agent_age() { echo $(( $(now) - ${1:-0} )); }
agent_status() { local a=$1 age beat; beat=$(load_field "$a" beat || echo 0); beat=${beat:-0}; age=$(agent_age "$beat"); if [ "$beat" -le 0 ] || [ "$age" -ge "$NO_OUT_MAX_SECONDS" ]; then echo NO-OUT; elif [ "$age" -ge "$NO_OUT_RECHECK_SECONDS" ]; then echo RECHECK-REQUIRED; elif [ "$age" -gt "$TTL" ]; then echo STALE; else echo ACTIVE; fi; }
is_no_out_agent() { [ "$(agent_status "$1")" = NO-OUT ]; }
is_stale_agent() { local status; status=$(agent_status "$1"); [ "$status" = STALE ] || [ "$status" = RECHECK-REQUIRED ] || [ "$status" = NO-OUT ]; }
is_auto_managed() { case "$1" in *.uid|*.import) return 0;; esac; case "$(basename "$1")" in CHANGELOG.md|change_index.json|narrative_chain.json|arcs.json|.commit_msg.txt) return 0;; esac; return 1; }
classify_file() { case "$1" in project.godot|scripts/preflight.gd|scripts/preflight/*|scripts/preflight_v2/*|scripts/testing/*|scripts/state/game_state.gd|scripts/state/run_save_data.gd|scripts/state/save_game_service.gd|scripts/state/domains/*) echo full;; *.md|*.json|*.svg|*.tres|*.png|*.jpg|*.jpeg|*.webp) echo python;; *) echo scoped;; esac; }
rank() { case "$1" in python) echo 0;; scoped) echo 1;; full) echo 2;; *) echo 1;; esac; }
max_level() { [ "$(rank "$1")" -ge "$(rank "$2")" ] && echo "$1" || echo "$2"; }
classify_list() { local out=python f; for f in "$@"; do out=$(max_level "$out" "$(classify_file "$f")"); done; echo "$out"; }
staged_files() { git diff --cached --name-only --diff-filter=ACMR; }
classify_staged() { mapfile -t _staged < <(staged_files); [ "${#_staged[@]}" -gt 0 ] || { echo python; return; }; classify_list "${_staged[@]}"; }
own_covers() { local a=$1 f=$2; grep -Fxq -- "$f" "$(files_file "$a")" 2>/dev/null || grep -q "|[^|]*|${f}$" "$(exc_file "$a")" 2>/dev/null || grep -q "|[^|]*|${f}$" "$(audit_file "$a")" 2>/dev/null; }
has_active_other_lock() { local f=$1 self=$2 a status; while IFS= read -r a; do [ "$a" = "$self" ] && continue; [ -f "$(reg_file "$a")" ] || continue; grep -Fxq -- "$f" "$(files_file "$a")" 2>/dev/null || continue; status=$(agent_status "$a"); [ "$status" = ACTIVE ] && { echo "$a"; return 0; }; done < <(list_agents); return 1; }
stale_holder() { local f=$1 self=$2 a; while read -r a; do [ "$a" = "$self" ] && continue; grep -Fxq -- "$f" "$(files_file "$a")" 2>/dev/null && is_stale_agent "$a" && { echo "$a"; return 0; }; done < <(list_agents); return 1; }
write_files() { local a=$1; shift; ensure_state >/dev/null; printf '%s\n' "$@" | sed '/^$/d' | sed 's/ -> .*//' | sort -u > "$(files_file "$a")"; }
check_in() {
  local a="" task="" ex="" reason=""; FILES=()
  while [ "$#" -gt 0 ]; do case "$1" in --agent) a=${2:-}; shift 2;; --task) task=${2:-}; shift 2;; --exception) ex=${2:-}; shift 2;; --reason) reason=${2:-}; shift 2;; --scope-file) [ -f "${2:-}" ] || die "Scope-Datei nicht gefunden" 2; mapfile -t FILES < "${2}"; shift 2;; --scope-from-staged) mapfile -t FILES < <(staged_files); shift;; --level) die "--level ist nicht zulässig" 2;; --files) shift; while [ "$#" -gt 0 ] && [[ "$1" != --* ]]; do FILES+=("$1"); shift; done;; *) die "unbekanntes Argument: $1" 2;; esac; done
  a=${a:-$(resolve_identity || true)}; [ -n "$a" ] || die "Agent-Identität fehlt" 2; [ "${#FILES[@]}" -gt 0 ] || die "--files erforderlich" 2
  if [ -n "$ex" ]; then case "$ex" in unowned|branch|emergency|legacy) ;; *) die "ungültige Exception" 2;; esac; [ -n "$reason" ] || die "--reason erforderlich" 2; else [ -n "$task" ] || die "--task erforderlich" 2; fi
  local f holder
  if [ "${AGENT_ACTIVITY_ADOPT_SCOPE:-0}" != "1" ]; then
    for f in "${FILES[@]}"; do if holder=$(has_active_other_lock "$f" "$a"); then die "Kollision: $f von $holder" 2; fi; done
  else
    journal "$a" adopt-scope "${#FILES[@]} files; existing branch scope explicitly adopted"
  fi
  local check_in_time existing_seed seed
  check_in_time=$(load_field "$a" in || true); check_in_time=${check_in_time:-$(now)}
  [ -n "$a" ] || die "Agent-Identität fehlt" 2
  existing_seed=$(load_field "$a" seed || true)
  seed=${existing_seed:-agent:$a:$(hostname 2>/dev/null || echo unknown):$$:$check_in_time}
  local doki_seed="${DOKI_AGENT_SEED:-}"
  if [ -n "$doki_seed" ]; then
    seed="agent:$a:doki:$doki_seed"
  fi
  local registry_file; registry_file=$(reg_file "$a"); ensure_state >/dev/null; { printf 'agent=%s\n' "$a"; printf 'pid=%s\n' "$$"; printf 'host=%s\n' "$(hostname 2>/dev/null || echo unknown)"; printf 'cwd=%s\n' "$(pwd)"; printf 'branch=%s\n' "$(git branch --show-current 2>/dev/null || echo unknown)"; printf 'head=%s\n' "$(git rev-parse HEAD 2>/dev/null || echo unknown)"; printf 'task=%s\n' "$task"; printf 'in=%s\n' "$check_in_time"; printf 'beat=%s\n' "$(now)"; printf 'status=ACTIVE\n'; printf 'seed=%s\n' "$seed"; printf 'updates=%s\n' "$(( $(load_field "$a" updates || echo 0) + 1 ))"; } > "$registry_file"; write_files "$a" "${FILES[@]}"
  if [ -n "$ex" ]; then printf '%s|%s|%s\n' "$(now)" "$ex" "${FILES[0]}" >> "$(exc_file "$a")"; journal "$a" exception "$ex:$reason"; else journal "$a" check-in "${FILES[*]}"; fi
  printf 'CHECKED IN: %s severity=%s\n' "$a" "$(classify_list "${FILES[@]}")"
}
update_agent() { local a=$(resolve_identity || true) reason="" branch=""; FILES=(); while [ "$#" -gt 0 ]; do case "$1" in --files) shift; while [ "$#" -gt 0 ] && [[ "$1" != --* ]]; do FILES+=("$1"); shift; done;; --branch) branch=${2:-}; shift 2;; --reason) reason=${2:-}; shift 2;; *) die "unbekanntes update-Argument" 2;; esac; done; [ -f "$(reg_file "$a")" ] || die "kein Check-In" 2; [ -n "$reason" ] || die "--reason erforderlich" 2; [ "${#FILES[@]}" -gt 0 ] && write_files "$a" "${FILES[@]}"; [ -n "$branch" ] && set_field "$a" branch "$branch"; set_field "$a" beat "$(now)"; set_field "$a" updates "$(( $(load_field "$a" updates || echo 0) + 1 ))"; journal "$a" update "$reason"; }
heartbeat() { local a=$(resolve_identity || true) from to; [ -f "$(reg_file "$a")" ] || die "kein Check-In" 2; from=$(load_field "$a" beat || echo 0); to=$(now); set_field "$a" beat "$to"; set_field "$a" status ACTIVE; journal "$a" heartbeat "from=$from to=$to reason=renewed files=$(tr '\n' ',' < "$(files_file "$a")" 2>/dev/null)"; }
check_out() { local a=$(resolve_identity || true) force=0; [ "${1:-}" = --force ] && force=1; [ -f "$(reg_file "$a")" ] || die "kein Check-In" 2; if [ "$force" = 0 ] && [ -n "$(git diff --cached --name-only --diff-filter=ACMR)" ]; then die "staged Arbeit vorhanden; nutze check-out --force nach Audit" 2; fi; set_field "$a" out "$(now)"; set_field "$a" beat 0; journal "$a" check-out "completed force=$force"; }
recheck_in() { local a=$(resolve_identity || true) audit=0 kind=unowned; FILES=(); reasons=(); while [ "$#" -gt 0 ]; do case "$1" in --audit) audit=1; shift;; --as) kind=${2:-}; shift 2;; --files) shift; while [ "$#" -gt 0 ] && [[ "$1" != --* ]]; do FILES+=("$1"); shift; done;; --file-reason) reasons+=("${2:-}"); shift 2;; *) die "unbekanntes recheck-in-Argument" 2;; esac; done; [ "$audit" = 1 ] || die "--audit erforderlich" 2; [ "${#FILES[@]}" -eq "${#reasons[@]}" ] || die "jeder Datei muss ein Reason zugeordnet sein" 2; local i; local from to; from=$(load_field "$a" beat || echo 0); to=$(now); for i in "${!FILES[@]}"; do [ -n "${reasons[$i]}" ] || die "leerer Datei-Reason" 2; printf '%s|%s|%s\n' "$to" "$kind" "${FILES[$i]}" >> "$(audit_file "$a")"; journal "$a" recheck-in "from=$from to=$to reason=${reasons[$i]} file=${FILES[$i]}"; done; set_field "$a" escalated 1; set_field "$a" beat "$to"; set_field "$a" status ACTIVE; }
check_files() { local a=$(resolve_identity || true) f h result=0 status; status=$(agent_status "$a" 2>/dev/null || echo ACTIVE); for f in "$@"; do if h=$(has_active_other_lock "$f" "$a"); then echo "$f FREMD-aktiv owner=$h"; result=2; elif h=$(stale_holder "$f" "$a"); then echo "$f FREMD-stale owner=$h"; elif [ "$status" = NO-OUT ]; then echo "$f NO-OUT-OWNER; re-check-in erforderlich"; result=1; elif own_covers "$a" "$f"; then echo "$f EIGEN"; else echo "$f UNIDENTIFIZIERT"; result=1; fi; done; return "$result"; }
prune_agents() { local force=0 purge=0 a archive; for x in "$@"; do [ "$x" = --force ] && force=1; [ "$x" = --purge ] && purge=1; done; for a in $(list_agents); do is_stale_agent "$a" || continue; archive="$(state_dir)/archive/${a}.$(now)"; if [ "$purge" = 1 ]; then rm -f "$(reg_file "$a")" "$(files_file "$a")" "$(exc_file "$a")" "$(audit_file "$a")"; journal "$a" prune purge; else { cat "$(reg_file "$a")"; printf '\n-- files --\n'; cat "$(files_file "$a")"; } > "$archive"; [ "$force" = 1 ] && rm -f "$(reg_file "$a")" "$(files_file "$a")"; journal "$a" prune archive; fi; done; }
takeover_cmd() { local a=$(resolve_identity || true) source=${1:-} reason=${2:-} from to files archive f holder; [ -n "$source" ] || die "takeover benötigt den Agenten" 2; [ -f "$(reg_file "$source")" ] || die "takeover Quelle nicht gefunden: $source" 2; is_stale_agent "$source" || die "takeover nur für stale/NO-OUT Agenten" 2; [ -f "$(reg_file "$a")" ] || die "takeover benötigt aktiven Check-In des neuen Agenten" 2; [ -n "$reason" ] || die "takeover benötigt reason" 2; while IFS= read -r f; do [ -z "$f" ] && continue; if holder=$(has_active_other_lock "$f" "$a"); then die "takeover Kollision: $f aktiv von $holder" 2; fi; done < "$(files_file "$source")"; from=$(load_field "$source" beat || echo 0); to=$(now); files=$(tr '\n' ',' < "$(files_file "$source")" 2>/dev/null); journal "$a" takeover "from=$source to=$a reason=$reason files=$files"; set_field "$a" takeover_from "$source"; set_field "$a" takeover_at "$to"; set_field "$a" takeover_reason "$reason"; set_field "$a" takeover_files "$files"; while IFS= read -r f; do [ -z "$f" ] || grep -Fxq -- "$f" "$(files_file "$a")" 2>/dev/null || printf '%s\n' "$f" >> "$(files_file "$a")"; done < "$(files_file "$source")"; sort -u "$(files_file "$a")" -o "$(files_file "$a")"; archive="$(state_dir)/archive/${source}.takeover.${to}"; { cat "$(reg_file "$source")"; printf '\n-- files --\n'; cat "$(files_file "$source")"; } > "$archive"; journal "$a" takeover-archive "from=$source to=$a reason=$reason files=$files archive=$archive"; }

branch_rewind() { local branch=$1 registered=$2 current; current=$(git rev-parse "$branch" 2>/dev/null || true); [ -n "$current" ] && [ -n "$registered" ] || return 0; if [ "$current" != "$registered" ] && git merge-base --is-ancestor "$current" "$registered" 2>/dev/null; then echo "AGENTGATE BLOCK: branch $branch hinter registriertem HEAD $registered; Remedy: merge/update/transfer"; return 1; fi; return 0; }
refresh_head() { local a=$1; [ -f "$(reg_file "$a")" ] && set_field "$a" head "$(git rev-parse HEAD 2>/dev/null || echo unknown)"; }
run_gate() {  local a=$(resolve_identity || true) staged f h bad=0 severity=python current_branch registered_branch registered_head
  heartbeat >/dev/null 2>&1 || true
  if [ -f "$(reg_file "$a")" ] && is_no_out_agent "$a"; then journal "$a" no-out "from=$(load_field "$a" beat || echo 0) to=$(now) reason=max-check-time files=$(tr '\n' ',' < "$(files_file "$a")" 2>/dev/null)"; echo "AGENTGATE NO-OUT: $a check-in expired; re-check-in required"; return 0; fi
  if [ -f "$(reg_file "$a")" ] && [ "$(agent_status "$a")" = RECHECK-REQUIRED ]; then journal "$a" recheck-required "from=$(load_field "$a" beat || echo 0) to=$(now) reason=one-hour-check"; echo "AGENTGATE WARN: $a re-check-in required after one hour"; fi
  staged=$(git diff --cached --name-only --diff-filter=ACMR); [ -n "$staged" ] || { echo 'AGENTGATE PASS: keine staged Dateien'; return; }
  if [ -n "${AGENT_ACTIVITY_SEED:-}" ]; then
    local registered_seed; registered_seed=$(load_field "$a" seed || true)
    [ -n "$registered_seed" ] && [ "$registered_seed" = "$AGENT_ACTIVITY_SEED" ] || { echo 'AGENTGATE BLOCK: AGENT_ACTIVITY_SEED mismatch or missing'; return 1; }
  fi
  [ -f "$(reg_file "$a")" ] || { echo "AGENTGATE BLOCK: kein Check-In; Remedy: check-in --agent $a --task ... --files ..."; return 1; }
  current_branch=$(git branch --show-current 2>/dev/null || echo unknown); registered_branch=$(load_field "$a" branch || echo ''); registered_head=$(load_field "$a" head || echo '')
  if [ -n "$registered_branch" ] && [ "$registered_branch" != "$current_branch" ]; then journal "$a" branch-mismatch "registered=$registered_branch current=$current_branch"; echo "AGENTGATE WARN: branch mismatch registered=$registered_branch current=$current_branch"; fi
  branch_rewind "$current_branch" "$registered_head" || bad=1
  while IFS= read -r f; do
    [ -z "$f" ] && continue; severity=$(max_level "$severity" "$(classify_file "$f")")
    if h=$(has_active_other_lock "$f" "$a"); then echo "AGENTGATE BLOCK: $f aktiv fremd gelockt von $h"; bad=1
    elif ! own_covers "$a" "$f" && ! is_auto_managed "$f"; then echo "AGENTGATE BLOCK: $f nicht abgedeckt; Remedy: update --files $f --reason \"...\""; bad=1; fi
  done <<< "$staged"
  [ "$bad" = 0 ] || return 1; refresh_head "$a"; if [ "$severity" = python ]; then echo "AGENTGATE PASS: $a severity=python (cheap verification path eligible)"; else echo "AGENTGATE PASS: $a severity=$severity"; fi
}
transfer_cmd() {
  local a=$(resolve_identity || true) source='' reason='' range='' continue_mode=0
  while [ "$#" -gt 0 ]; do case "$1" in --from) source=${2:-}; shift 2;; --commits) range=${2:-}; shift 2;; --reason) reason=${2:-}; shift 2;; --continue) continue_mode=1; shift;; *) die "unbekanntes transfer-Argument" 2;; esac; done
  [ -n "$reason" ] || die "transfer benötigt --reason" 2
  if [ "$continue_mode" = 1 ]; then local continue_status=$?; git cherry-pick --continue; continue_status=$?; [ "$continue_status" -eq 0 ] && journal "$a" transfer_complete "from=$(load_field "$a" head || echo unknown) to=$(git rev-parse HEAD 2>/dev/null || echo unknown) reason=transfer-continue files=conflict-resolved"; return "$continue_status"; fi
  [ -n "$source" ] || die "transfer benötigt --from" 2; [ "$(git branch --show-current)" = main ] || die "Transfer nur auf main" 2
  [ -f "$(reg_file "$a")" ] || die "Transfer-Gate: kein aktiver Check-In" 1
  is_no_out_agent "$a" && die "Transfer-Gate: Check-In ist NO-OUT; neuer Check-In erforderlich" 1
  local source_files sf holder
  source_files=$(git diff-tree --no-commit-id --name-only -r "${range:-$source}" 2>/dev/null || true)
  while IFS= read -r sf; do
    [ -z "$sf" ] && continue
    if holder=$(has_active_other_lock "$sf" "$a"); then die "Transfer-Gate: Quell-Datei $sf aktiv von $holder gelockt" 1; fi
  done <<< "$source_files"
  run_gate || die "Transfer-Gate blockiert den Cherry-Pick" 1
  local head=$(git rev-parse "$source" 2>/dev/null || die "Quelle nicht gefunden" 2) rec="$(state_dir)/transfers/$(now)-${source//\//_}"
  if grep -R -q "source_head=$head" "$(state_dir)/transfers" 2>/dev/null; then echo 'TRANSFER NO-OP: bereits importiert'; return; fi
  printf 'agent=%s\nsource=%s\nsource_head=%s\ntarget=main\nreason=%s\nin=%s\n' "$a" "$source" "$head" "$reason" "$(now)" > "$rec"
  git log --format=%H "${range:-$source}" -1 > "$rec.files"; journal "$a" transfer_gate "$source:$head"
  git cherry-pick "${range:-$source}" || { journal "$a" transfer_conflict "$source"; return 1; }
  set_field "$a" head "$(git rev-parse HEAD)"; set_field "$a" imports "$(( $(load_field "$a" imports || echo 0) + 1 ))"; journal "$a" transfer_complete "$source"
}
self_test() {
  local tmp; tmp=$(mktemp -d); export AGENT_ACTIVITY_DIR="$tmp/state" AGENT_NAME=self-test
  "$0" check-in --agent self-test --task smoke --files scripts/agent_activity.sh >/dev/null
  "$0" heartbeat >/dev/null
  "$0" update --files scripts/agent_activity.sh --reason "self-test causal update" >/dev/null
  "$0" recheck-in --audit --files docs/AGENT_ACTIVITY.md --file-reason "docs/AGENT_ACTIVITY.md:legacy audit" --as legacy >/dev/null
  "$0" check docs/AGENT_ACTIVITY.md >/dev/null
  "$0" status --all >/dev/null
  local rewind_result collision_result prune_result
  local registered_head; registered_head=$(git rev-parse HEAD); if branch_rewind HEAD "$registered_head" >/dev/null 2>&1; then :; else echo 'self-test rewind smoke failed'; rm -rf "$tmp"; return 1; fi
  if branch_rewind HEAD "$(git rev-parse HEAD^ 2>/dev/null)" >/dev/null 2>&1; then :; else echo 'self-test rewind smoke failed'; rm -rf "$tmp"; return 1; fi
  AGENT_ACTIVITY_DIR="$tmp/collision" AGENT_NAME=owner "$0" check-in --agent owner --task lock --files collision.txt >/dev/null
  if AGENT_ACTIVITY_DIR="$tmp/collision" AGENT_NAME=other "$0" check-in --agent other --task collision --files collision.txt >/dev/null 2>&1; then echo 'self-test collision smoke failed'; rm -rf "$tmp"; return 1; fi
  AGENT_ACTIVITY_DIR="$tmp/prune" AGENT_NAME=stale "$0" check-in --agent stale --task prune --files stale.txt >/dev/null
  sed -i 's/^beat=.*/beat=0/' "$tmp/prune/agents/stale"
  AGENT_ACTIVITY_DIR="$tmp/prune" AGENT_NAME=stale "$0" prune --force >/dev/null
  [ ! -f "$tmp/prune/agents/stale" ] || { echo 'self-test prune smoke failed'; rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"; echo 'AGENTGATE SELF-TEST: PASSED'
}
status_cmd() { local a f; [ "${1:-}" = --all ] && shift; for a in $(list_agents); do echo "$a pid=$(load_field "$a" pid) host=$(load_field "$a" host) branch=$(load_field "$a" branch) head=$(load_field "$a" head) seed=$(load_field "$a" seed) age=$(agent_age "$(load_field "$a" beat)")s status=$(agent_status "$a") escalated=$(load_field "$a" escalated || echo 0) imports=$(load_field "$a" imports || echo 0)"; echo -n '  files: '; tr '\n' ' ' < "$(files_file "$a")" 2>/dev/null || true; echo; done; echo 'ARCHIVE:'; for f in "$(state_dir)"/archive/*; do [ -f "$f" ] && echo "  $f"; done; echo 'JOURNAL:'; [ -f "$(state_dir)/journal.log" ] && tail -20 "$(state_dir)/journal.log" || true; echo 'TRANSFERS:'; for f in "$(state_dir)"/transfers/*; do [ -f "$f" ] && echo "  $f"; done; }
usage() { echo 'AgentGate: check-in|update|heartbeat|check-out|status|check|recheck-in|takeover|prune|transfer|gate|run-preflight|classify-staged|self-test'; }
cmd=${1:-}; shift || true
case "$cmd" in
  gate|run-preflight)
    # Preflight ruft den Gate ohne Shell-Umgebung auf; Identität kommt als Flag.
    while [ "$#" -gt 0 ]; do case "$1" in
      --agent) export AGENT_NAME=${2:-}; shift 2;;
      *) shift;;
    esac; done;;
esac
case "$cmd" in seed) seed_for "${1:-}";; classify-staged) classify_staged;; check-in) check_in "$@";; update) update_agent "$@";; heartbeat) heartbeat;; check-out) check_out "$@";; status) status_cmd;; check) check_files "$@";; recheck-in) recheck_in "$@";; takeover) takeover_cmd "${1:-}" "${2:-}";; prune) prune_agents "$@";; transfer) transfer_cmd "$@";; gate|run-preflight) run_gate;; self-test) self_test;; *) usage; exit 2;; esac
