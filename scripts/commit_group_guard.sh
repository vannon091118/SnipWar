#!/usr/bin/env bash
# commit_group_guard.sh — Atomare Commit-Gruppen maschinell erzwingen (AGENTS.md).
#
# Hintergrund (Drift-Audit F3, Commit 8a1eeb2): Ein Commit mischte 8+ Domänen
# (167 Dateien) und brach damit die Verträgen der atomaren Commit-Gruppen.
# Dieser Guard blockiert Staged-Sets, deren Dateien zu disjunkten Gruppen gehören.
#
# Semantik: Jede Datei erhält die Menge der Gruppen, in denen sie laut
# AGENTS.md-Tabelle steht (Bitmaske; Overlaps wie game_state.gd ∈ Transit+
# GameState+Save sind intendiert). Verletzt ist ein Commit, wenn ZWEI staged
# Dateien disjunkte Gruppenmengen haben — dann mischt er Domänen ohne
# gemeinsamen Schnitt. Dateien ohne Tabellen-Eintrag (Tests, Docs, Assets)
# sind "ungrouped" (Maske 0) und tragen nicht zur Verletzung bei.
#
# Subkommandos:
#   check [--allow-multi <grund>] [--files f1 f2 ...]  Exit 1 bei Verletzung.
#       Ohne --files: staged Dateien (git diff --cached, ACMR).
#       --allow-multi: bewusste Takeover-Ausnahme; Grund muss als
#       [TAKEOVER: <grund>]-Zeile in den Commit-Body (wird ausgegeben).
#   classify <files...>       Gruppen pro Datei anzeigen (Debug).
#   self-test                 Regressionsszenarien, exit != 0 bei Fehlschlag.

set -u -o pipefail

# Gruppen-Bits (AGENTS.md "Atomare Commit-Gruppen")
G_TRANSIT=1; G_NAV=2; G_PLANETS=4; G_GAMESTATE=8; G_SHIPS=16; G_COMBAT=32
G_WORLD=64; G_SECTOR=128; G_SAVE=256; G_CONCEPT=512; G_GLOBALSEARCH=1024
G_DOKI=2048; G_NARRATIVE=4096

# preflight.gd steht laut Tabelle in allen zehn Domänen-Gruppen.
MASK_PREFLIGHT=$((G_TRANSIT|G_NAV|G_PLANETS|G_GAMESTATE|G_SHIPS|G_COMBAT|G_WORLD|G_SECTOR|G_SAVE|G_CONCEPT))

group_mask() {
  local f="$1"
  case "$f" in
    # Auto-managed Ride-alongs (DOKI-Artefakte, Sidecars) — nie klassifizieren.
    *.uid|*.import) echo 0; return;;
    CHANGELOG.md|change_index.json|narrative_chain.json|arcs.json|scripts/doki/data/arcs.json|.commit_msg.txt) echo 0; return;;
    .doki/*|.freebuff/*|.agents/*|.claude/*) echo 0; return;;
    scripts/doki/NARRATIVE_ENGINE_DESIGN.md) echo $((G_DOKI|G_NARRATIVE)); return;;
    scripts/doki/*) echo $G_DOKI; return;;
    .githooks/*) echo $G_DOKI; return;;
    narrative_runtime/*) echo $G_NARRATIVE; return;;
    .gitignore) echo $G_NARRATIVE; return;;
    AGENTS.md) echo $((G_DOKI|G_GLOBALSEARCH|G_NARRATIVE)); return;;
    scripts/concept_index.gd) echo $((G_CONCEPT|G_DOKI)); return;;
    scripts/global_search.gd) echo $G_GLOBALSEARCH; return;;
    scripts/preflight.gd) echo "$MASK_PREFLIGHT"; return;;
    scripts/state/game_state.gd) echo $((G_TRANSIT|G_GAMESTATE|G_SAVE)); return;;
    scripts/state/run_save_data.gd) echo $G_SAVE; return;;
    scripts/state/save_game_service.gd) echo $G_SAVE; return;;
    scripts/state/domains/*) echo $((G_GAMESTATE|G_SAVE)); return;;
    *bootstrap.gd) echo $G_GAMESTATE; return;;
    scripts/flight_time.gd|scripts/dispatch.gd|*worker_cluster.*) echo $G_TRANSIT; return;;
    *planet_network.gd|*worker_manager.gd) echo $((G_TRANSIT|G_NAV)); return;;
    *navigation_field.gd) echo $((G_NAV|G_WORLD)); return;;
    *navigation_waypoint.gd) echo $G_NAV; return;;
    *seeded_layout.gd) echo $((G_NAV|G_PLANETS|G_SECTOR|G_SAVE)); return;;
    */planet.tscn|scripts/objects/planets/planet.gd|*planet_arrival_resolver.gd|*planet_trait_aggregator.gd|*planet_view.gd) echo $G_PLANETS; return;;
    *ship_part_definition.gd|*ship_blueprint.gd|*ship_part_catalog*|*technology_definition.gd|*ship_manager.gd|scripts/ui/dossier/*) echo $G_SHIPS; return;;
    *fleet_battle_simulator.gd|*conquest_simulator.gd|*composite_ship_view.gd|*conflict_manager.gd|*fleet_snapshot.gd) echo $G_COMBAT; return;;
    scenes/*battle*|scenes/*conquest*) echo $G_COMBAT; return;;
    *world_config.gd) echo $((G_WORLD|G_SECTOR)); return;;
    scripts/history/*) echo $G_COMBAT; return;;  # Chronik: Kampf&Simulation-Adjazenz (Audit F1)
    *world_generator.gd|*chunk_coordinator.gd|*planet_procedural.gd) echo $G_WORLD; return;;
    *sector_flavor*|*sector_anchor.gd|*sector_classifier.gd) echo $G_SECTOR; return;;
    *resource_pool*.tres) echo $G_GAMESTATE; return;;
    scripts/ui/main_menu.gd|scripts/ui/pause/*) echo $G_SAVE; return;;
    *constraint_concept_index.gd|*mechanic_registry.gd|*scenario_loader.gd|*scenario_snapshot.gd) echo $G_CONCEPT; return;;
    *) echo 0; return;;
  esac
}

mask_names() {
  local m="$1" out="" bit label
  local labels=(
    "1:Transit&Dispatch" "2:Navigation" "4:Planeten&Katalog" "8:GameState&Ressourcen"
    "16:Schiffsbau&Forschung" "32:Kampf&Simulation" "64:Prozedurale Welt" "128:SectorSystem"
    "256:Save/Load" "512:ConceptIndex&Suche" "1024:Global Search" "2048:DOKI CommitLayer"
    "4096:Narrative Runtime"
  )
  for entry in "${labels[@]}"; do
    bit=${entry%%:*}; label=${entry#*:}
    if (( (m & bit) != 0 )); then out+="${out:+, }${label}"; fi
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

  local masks=() f m grouped=0
  for f in "${FILES[@]}"; do
    m=$(group_mask "$f") || return 2
    [ "$m" -gt 0 ] || continue
    masks+=("$m|$f")
    grouped=$((grouped+1))
  done

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
  # Gemeinsamer Schnitt muss durchgehen (Overlaps der Tabelle).
  expect_pass scripts/state/game_state.gd scripts/state/save_game_service.gd
  expect_pass scripts/state/game_state.gd scripts/flight_time.gd
  expect_pass scripts/doki/core/verifier.gd .githooks/pre-commit
  expect_pass AGENTS.md scripts/global_search.gd
  expect_pass scripts/preflight.gd scripts/objects/ships/ship_manager.gd
  # Ungrouped/leer stört nie.
  expect_pass README.md docs/FINDINGS.md
  expect_pass scripts/testing/test_all.gd scripts/flight_time.gd
  expect_pass scripts/state/game_state.gd
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
