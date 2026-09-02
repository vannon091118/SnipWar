#!/usr/bin/env bash
# commit_group_guard.sh — Atomare Commit-Gruppen maschinell erzwingen (AGENTS.md).
#
# Hintergrund (Drift-Audit F3, Commit 8a1eeb2): Ein Commit mischte 8+ Domänen
# (167 Dateien) und brach damit die Verträgen der atomaren Commit-Gruppen.
# Dieser Guard blockiert Staged-Sets, deren Dateien zu disjunkten Gruppen gehören.
#
# V3-009 (Vertrags-SSOT): Die Pfad→Gruppen-Tabelle lebt in
# scripts/preflight_v2/contract_map.json — dieselbe Quelle, aus der auch der
# ChangeImpactResolver die Contracts liest (constraint_scanner.path_contracts).
# Zwei Karten für dasselbe Terrain waren der nächste Driftgenerator; jetzt
# liest der Guard seine Gruppierung aus der SSOT.
#
# Semantik: Jede Datei erhält die Menge der Gruppen, in denen sie laut SSOT
# steht (Bitmaske; Overlaps wie game_state.gd ∈ Transit+GameState+Save sind
# intendiert). Verletzt ist ein Commit, wenn ZWEI staged Dateien disjunkte
# Gruppenmengen haben — dann mischt er Domänen ohne gemeinsamen Schnitt.
# Gruppen-Sonderwerte in der SSOT:
#   "AUTO"       → Maske 0 (auto-managed Ride-alongs: DOKI-Artefakte, Docs, Sidecars).
#   "ALL_DOMAINS"→ Maske aller Domänen-Gruppen (preflight-Infrastruktur).
# V3-009 fail-closed: Eine Datei, die KEINER SSOT-Regel matcht, ist ein
# FEHLER (unclassified), kein stiller Ride-along mehr — sie hätte sonst
# beliebige Domain-Dateien begleiten können.
#
# Subkommandos:
#   check [--allow-multi <grund>] [--files f1 f2 ...]  Exit 1 bei Verletzung.
#       Ohne --files: staged Dateien (git diff --cached, ACMRD).
#       --allow-multi: bewusste Takeover-Ausnahme; Grund muss als
#       [TAKEOVER: <grund>]-Zeile in den Commit-Body (wird ausgegeben).
#   classify <files...>       Gruppen pro Datei anzeigen (Debug).
#   self-test                 Regressionsszenarien, exit != 0 bei Fehlschlag.

set -u -o pipefail

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONTRACT_MAP="$ROOT_DIR/scripts/preflight_v2/contract_map.json"

# Gruppen-Bits (Reihenfolge = SSOT "groups"-Array; Bit i = 1<<i).
declare -a GROUP_NAMES=()
declare -A GROUP_BIT=()
G_BIT_ALL_DOMAINS=0   # Maske aller Domänen-Gruppen (aus der SSOT gebaut)

# load_contract_map — parst die SSOT einmal in Bash-Arrays.
# Setzt: SSOT_OK, SSOT_RULES_GLOB[], SSOT_RULES_GROUPS[][1], GROUP_BIT, G_BIT_ALL_DOMAINS.
load_contract_map() {
  SSOT_OK=0
  SSOT_RULES_GLOB=()
  SSOT_RULES_GROUPS=()
  GROUP_NAMES=()
  GROUP_BIT=()
  G_BIT_ALL_DOMAINS=0
  if [ ! -f "$CONTRACT_MAP" ]; then
    echo "GUARD ERROR: contract_map.json fehlt: $CONTRACT_MAP" >&2
    return 2
  fi
  python - "$CONTRACT_MAP" <<'PYEOF' > "$ROOT_DIR/.guard_ssot.tmp.$$"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
names = data["groups"]
print("\t".join(names))
for rule in data["rules"]:
    groups = rule["groups"]
    if groups == "ALL_DOMAINS":
        enc = "ALL"
    elif groups == "AUTO":
        enc = ""
    else:
        enc = ",".join(groups)
    print("%s\t%s" % (rule["glob"], enc))
PYEOF
  local rc=$?
  if [ $rc -ne 0 ]; then
    echo "GUARD ERROR: contract_map.json unlesbar/ungültig" >&2
    rm -f "$ROOT_DIR/.guard_ssot.tmp.$$"
    return 2
  fi
  local line i=0
  local first=1
  while IFS= read -r line; do
    if [ "$first" -eq 1 ]; then
      first=0
      local idx=0 bit=1
      line=${line%$'\r'}
      IFS=$'\t' read -r -a GROUP_NAMES <<< "$line"
      for name in "${GROUP_NAMES[@]}"; do
        GROUP_BIT["$name"]=$bit
        G_BIT_ALL_DOMAINS=$((G_BIT_ALL_DOMAINS | bit))
        bit=$((bit << 1))
        idx=$((idx+1))
      done
      continue
    fi
    local glob=${line%%$'\t'*}
    local groups=${line#*$'\t'}
    # Windows-Python schreibt CRLF — Zeilenenden normalisieren.
    glob=${glob%$'\r'}
    groups=${groups%$'\r'}
    SSOT_RULES_GLOB+=("$glob")
    SSOT_RULES_GROUPS+=("$groups")
  done < "$ROOT_DIR/.guard_ssot.tmp.$$"
  rm -f "$ROOT_DIR/.guard_ssot.tmp.$$"
  SSOT_OK=1
  return 0
}

# glob_match path glob — Bash-Implementierung der SSOT-Glob-Semantik:
#   prefix**, prefix/**, *-Wildcards (kein leeres Zwischen-Segment-Trap),
#   exakte Pfade. FIRST MATCH WINS (Regelreihenfolge = SSOT-Reihenfolge).
glob_match() {
  local path="$1" glob="$2"
  case "$glob" in
    "*") return 0;;
  esac
  if [[ "$glob" == "**" ]]; then
    [[ "$path" == "$glob" || "$path" == "${glob%\*\*}"* ]] && return 0 || return 1
  fi
  if [[ "$glob" == "/**" ]]; then
    [[ "$path" == "$glob" || "$path" == "${glob%/\*\*}"/* ]] && return 0 || return 1
  fi
  case "$glob" in
    "**") return 0;;
  esac
  # prefix/**  →  path unter prefix
  if [[ "$glob" == *"/**" ]]; then
    local base="${glob%/\*\*}"
    [[ "$path" == "$base" || "$path" == "$base"/* ]] && return 0 || return 1
  fi
  # prefix** → begins_with prefix
  if [[ "$glob" == *"**" ]]; then
    [[ "$path" == "${glob%\*\*}"* ]] && return 0 || return 1
  fi
  if [[ "$glob" == *"**/"* ]]; then
    # **/foo → jede Tiefe: vereinfacht als ends_with und contains
    local tail="${glob#*\*\*/}"
    [[ "$path" == "$tail" || "$path" == */"$tail" ]] && return 0 || return 1
  fi
  if [[ "$glob" == *"**"* ]]; then
    # Segment-Form wie "a/**/b": vereinfachtes Containment
    local pre="${glob%%\*\**}"
    local post="${glob##*\*\*/}"
    [[ "$path" == "$pre"* && ( "$path" == *"$post" || "$post" == "" ) ]] && return 0 || return 1
  fi
  if [[ "$glob" == *"*"* ]]; then
    # Wildcard mit Segmenten: prefix, suffix, geordnete Zwischensegmente.
    local segs=()
    local IFS='*'
    read -r -a segs <<< "$glob"
    unset IFS
    local prefix="${segs[0]}"
    local n=${#segs[@]}
    local suffix="${segs[$((n-1))]}"
    [[ "$path" == "$prefix"* ]] || return 1
    if [ -n "$suffix" ]; then
      [[ "$path" == *"$suffix" ]] || return 1
    fi
    local cursor=${#prefix}
    local ceiling=$(( ${#path} - ${#suffix} ))
    local i
    for ((i=1; i<n-1; i++)); do
      local seg="${segs[$i]}"
      [ -z "$seg" ] && continue
      local rest="${path:$cursor}"
      local off
      off=$(printf '%s' "$rest" | grep -boF -- "$seg" 2>/dev/null | head -1 | cut -d: -f1)
      if [ -z "$off" ]; then return 1; fi
      if [ $((cursor + off + ${#seg})) -gt "$ceiling" ]; then return 1; fi
      cursor=$((cursor + off + ${#seg}))
    done
    return 0
  fi
  [ "$path" = "$glob" ]
}

# group_mask path → Maske; echo "ERR" bei unclassified (fail-closed), "ERR2" bei SSOT-Bruch.
group_mask() {
  local f="$1" i glob groups enc name
  if [ "$SSOT_OK" -ne 1 ]; then
    echo "ERR2"; return
  fi
  for i in "${!SSOT_RULES_GLOB[@]}"; do
    glob="${SSOT_RULES_GLOB[$i]}"
    if glob_match "$f" "$glob"; then
      groups="${SSOT_RULES_GROUPS[$i]}"
      if [ "$groups" = "ALL" ]; then
        echo "$G_BIT_ALL_DOMAINS"; return
      fi
      if [ -z "$groups" ]; then
        echo 0; return
      fi
      local mask=0
      IFS=',' read -r -a enc <<< "$groups"
      for name in "${enc[@]}"; do
        local bit=${GROUP_BIT[$name]:-0}
        if [ "$bit" -eq 0 ] && [ "$name" != "transit" ]; then
          echo "ERR2"; return
        fi
        mask=$((mask | bit))
      done
      echo "$mask"; return
    fi
  done
  echo "ERR"; return
}

mask_names() {
  local m="$1" out="" bit i
  if [ "$m" = "ERR" ] || [ "$m" = "ERR2" ]; then
    echo "unclassified"
    return
  fi
  for ((i=0; i<${#GROUP_NAMES[@]}; i++)); do
    bit=$((1 << i))
    if (( (m & bit) != 0 )); then out+="${out:+, }${GROUP_NAMES[$i]}"; fi
  done
  echo "${out:-ungrouped}"
}

cmd_check() {
  local allow=0 reason="" FILES=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --allow-multi) allow=1; reason=${2:-}; shift 2;;
      --files) shift; while [ "$#" -gt 0 ] && [[ "$1" != --* ]]; do FILES+=("$1"); shift; done;;
      *) printf 'GUARD ERROR: unbekanntes Argument: %s\n' "$1" >&2; return 2;;
    esac
  done
  if [ "${#FILES[@]}" -eq 0 ]; then
    mapfile -t FILES < <(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null)
  fi

  load_contract_map || return 2

  local masks=() f m grouped=0 unclassified=0
  for f in "${FILES[@]}"; do
    m=$(group_mask "$f") || return 2
    if [ "$m" = "ERR" ]; then
      printf 'GUARD BLOCK: unklassifizierte Datei "%s" — kein SSOT-Eintrag (fail-closed, V3-009)\n' "$f" >&2
      unclassified=$((unclassified+1))
      continue
    fi
    if [ "$m" = "ERR2" ]; then
      echo "GUARD ERROR: SSOT-Verstoß beim Klassifizieren von $f" >&2
      return 2
    fi
    [ "$m" -gt 0 ] || continue
    masks+=("$m|$f")
    grouped=$((grouped+1))
  done

  if [ "$unclassified" -gt 0 ]; then
    printf 'Remedy: Pfad-Regel in scripts/preflight_v2/contract_map.json ergänzen (glob + contracts + groups) ODER --allow-multi mit Grund.\n' >&2
    return 1
  fi

  if [ "$grouped" -le 1 ]; then
    echo "COMMIT-GROUP GUARD: PASS (${grouped} gruppierte Datei(en), ${#FILES[@]} staged)"
    return 0
  fi

  local i j mi mj fi fj bad=0 shown=0
  for ((i=0; i<${#masks[@]}; i++)); do
    mi=${masks[$i]%%|*}; fi=${masks[$i]#*|}
    for ((j=i+1; j<${#masks[@]}; j++)); do
      mj=${masks[$j]%%|*}; fj=${masks[$j]#*|}
      if (( (mi & mj) == 0 )); then
        if [ "$shown" -lt 10 ]; then
          printf 'COMMIT-GROUP GUARD BLOCK: "%s" [%s] und "%s" [%s] — disjunkte atomare Gruppen\n' \
            "$fi" "$(mask_names "$mi")" "$fj" "$(mask_names "$mj")"
          shown=$((shown+1))
        fi
        bad=1
      fi
    done
  done

  if [ "$bad" -eq 0 ]; then
    echo "COMMIT-GROUP GUARD: PASS (${grouped} gruppierte Dateien, gemeinsamer Schnitt vorhanden)"
    return 0
  fi

  if [ "$allow" -eq 1 ]; then
    if [ -z "$reason" ]; then
      printf 'GUARD ERROR: --allow-multi ohne Begründung unzulässig\n' >&2
      return 2
    fi
    echo "COMMIT-GROUP GUARD: ALLOW-MULTI (bewusste Ausnahme)."
    echo "Pflicht: Zeile '[TAKEOVER: ${reason}]' in den Commit-Body aufnehmen."
    return 0
  fi

  printf 'Remedy: Commit auf eine Gruppe beschränken ODER bewusst takeovern:\n' >&2
  printf '  bash scripts/commit_group_guard.sh check --allow-multi "<grund>"\n' >&2
  return 1
}

cmd_classify() {
  load_contract_map || return 2
  local f m
  for f in "$@"; do
    m=$(group_mask "$f")
    printf '%-60s %s\n' "$f" "$(mask_names "$m")"
  done
}

cmd_self_test() {
  local failures=0
  expect_block() {
    if cmd_check --files "$@" >/dev/null 2>&1; then
      echo "self-test FAIL (erwartete BLOCK): $*"; failures=$((failures+1))
    fi
  }
  expect_pass() {
    if ! cmd_check --files "$@" >/dev/null 2>&1; then
      echo "self-test FAIL (erwartete PASS): $*"; failures=$((failures+1))
    fi
  }
  # Disjunkte Domänen müssen blocken.
  expect_block scripts/flight_time.gd scripts/objects/ships/ship_manager.gd
  expect_block scripts/dispatch.gd scripts/doki/core/verifier.gd
  # History-Chronik ist der Kampf-Domäne adjazend, nicht disjunkt:
  # gemeinsamer Schnitt -> PASS (F1-Grenze wird inhaltlich, nicht per Guard, gezogen).
  expect_pass scripts/objects/conflict_manager.gd scripts/history/world_chronicle.gd
  expect_block .githooks/pre-commit scripts/objects/ships/ship_manager.gd
  # Gemeinsamer Schnitt muss durchgehen (Overlaps der SSOT).
  expect_pass scripts/state/game_state.gd scripts/state/save_game_service.gd
  expect_pass scripts/state/game_state.gd scripts/flight_time.gd
  expect_pass scripts/doki/core/verifier.gd .githooks/pre-commit
  expect_pass AGENTS.md scripts/global_search.gd
  expect_pass scripts/preflight.gd scripts/objects/ships/ship_manager.gd
  # AUTO-Ride-alongs (Docs, DOKI-Artefakte) stören nie.
  expect_pass README.md docs/FINDINGS.md
  expect_pass scripts/testing/test_all.gd scripts/flight_time.gd
  expect_pass scripts/state/game_state.gd
  # V3-009 fail-closed: unklassifizierte Datei blockiert jetzt.
  expect_block totally/unknown/newfile.xyz
  expect_block scripts/state/game_state.gd totally/unknown/newfile.xyz
  # allow-multi ohne Grund ist ein Fehler; mit Grund geht durch.
  if cmd_check --allow-multi "" --files scripts/flight_time.gd scripts/doki/x.gd >/dev/null 2>&1; then
    echo "self-test FAIL (allow-multi ohne Grund musste fehlschlagen)"; failures=$((failures+1))
  fi
  if ! cmd_check --allow-multi "koordinierter Twin-Commit" --files scripts/flight_time.gd scripts/doki/x.gd >/dev/null 2>&1; then
    echo "self-test FAIL (allow-multi mit Grund musste durchgehen)"; failures=$((failures+1))
  fi
  if [ "$failures" -eq 0 ]; then
    echo "COMMIT-GROUP GUARD SELF-TEST: PASSED"
    return 0
  fi
  echo "COMMIT-GROUP GUARD SELF-TEST: ${failures} FEHLER"
  return 1
}

cmd="${1:-}"; shift || true
case "$cmd" in
  check) cmd_check "$@";;
  classify) cmd_classify "$@";;
  self-test) cmd_self_test;;
  *) echo "usage: commit_group_guard.sh check|classify|self-test"; exit 2;;
esac
