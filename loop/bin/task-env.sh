#!/usr/bin/env bash
# task-env.sh — per-task isolated app+DB environment for the loop engine.
#
# Each task (= one git worktree) gets its OWN Docker Compose stack: an isolated
# project name (its own containers, volumes, network and DB) plus host ports the
# Docker daemon assigns automatically — so 1–10 tasks run in parallel without
# colliding, and any tester/dev can bring one up and read its URLs in one command.
#
# We deliberately let Docker pick host ports (publish the container port with no
# host side) and read them back with `docker compose port`. No free-port scan, so
# no race between "find a free port" and "bind it".
#
# Usage:
#   task-env.sh up    <task-id> [worktree-dir]   # ensure the stack is up; print manifest JSON
#   task-env.sh ports <task-id> [worktree-dir]   # print the saved manifest (URLs/ports) for a task
#   task-env.sh down  <task-id> [worktree-dir]   # tear the task's stack down (containers + volumes)
#   task-env.sh list                             # list loop task stacks, their ports, and the latest progress line
#   task-env.sh statedir                         # print the per-task state dir (plans/manifests/journals live here, NOT in any repo)
#   task-env.sh log   <task-id> <text...>        # append a 1-3 line progress note to the task's journal
#   task-env.sh progress <task-id>               # print the task's progress journal (running context for any agent)
#   task-env.sh selfcheck                        # offline assertions (no docker needed)
#
# Env overrides: LOOP_COMPOSE_FILE (force a compose file), LOOP_ENV_DIR (manifest/registry dir).
set -euo pipefail

ENV_DIR="${LOOP_ENV_DIR:-$HOME/.cache/loop-engine}"
mkdir -p "$ENV_DIR"

die() { echo "task-env: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

detect_compose() {
  local wt="$1"
  if [ -n "${LOOP_COMPOSE_FILE:-}" ]; then echo "$LOOP_COMPOSE_FILE"; return; fi
  local f
  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    [ -f "$wt/$f" ] && { echo "$wt/$f"; return; }
  done
  return 1
}

proj_name() { # <task-id> <worktree> -> docker-safe project name, namespaced by repo
  local task="$1" wt="$2" repo
  repo="$(basename "$(cd "$wt" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "$wt")")"
  echo "loop_${repo}_${task}" | tr '[:upper:] ' '[:lower:]_' | tr -cd 'a-z0-9_-'
}

# Resolve the base compose to a single generated file with host ports stripped,
# so Docker assigns ephemeral host ports (the only -f, so no append-merge surprises).
gen_compose() { # <base> <out>
  docker compose -f "$1" config --format json \
    | jq 'del(.name)
          | .services |= with_entries(.value.ports = ((.value.ports // []) | map(del(.published))))' \
    > "$2"
}

db_url_for() { # <generated> <service> <hostport> -> a url if it looks like a known db, else ""
  local gen="$1" svc="$2" hp="$3" img env
  img="$(jq -r --arg s "$svc" '.services[$s].image // ""' "$gen")"
  env="$(jq -r --arg s "$svc" '.services[$s].environment // {} | to_entries|map("\(.key)=\(.value)")|.[]' "$gen")"
  get() { local v; v="$(echo "$env" | sed -n "s/^$1=//p" | head -1)"; echo "${v:-$2}"; }
  case "$svc $img" in
    *postgres*|*pg*) echo "postgres://$(get POSTGRES_USER postgres):$(get POSTGRES_PASSWORD postgres)@localhost:$hp/$(get POSTGRES_DB postgres)" ;;
    *mysql*|*maria*) echo "mysql://root:$(get MYSQL_ROOT_PASSWORD root)@localhost:$hp/$(get MYSQL_DATABASE app)" ;;
    *) echo "" ;;
  esac
}

build_manifest() { # <task> <wt> <proj> <base> <gen> -> manifest json on stdout
  local task="$1" wt="$2" proj="$3" base="$4" gen="$5"
  local services="{}" primary="" svc cport hostmap hp url dburl
  for svc in $(jq -r '.services|keys[]' "$gen"); do
    local ports="[]"
    for cport in $(jq -r --arg s "$svc" '.services[$s].ports[]?.target // empty' "$gen"); do
      hostmap="$(COMPOSE_PROJECT_NAME="$proj" docker compose -f "$gen" port "$svc" "$cport" 2>/dev/null || true)"
      hp="${hostmap##*:}"; [ -z "$hp" ] && continue
      url="http://localhost:$hp"
      ports="$(echo "$ports" | jq --argjson c "$cport" --argjson h "$hp" --arg u "$url" '. + [{container:$c,host:$h,url:$u}]')"
      case "$svc" in web|app|frontend|client|ui) [ -z "$primary" ] && primary="$url" ;; esac
    done
    [ "$ports" = "[]" ] && continue
    local svc_obj; svc_obj="$(jq -n --argjson p "$ports" '{ports:$p}')"
    hp="$(echo "$ports" | jq -r '.[0].host')"
    dburl="$(db_url_for "$gen" "$svc" "$hp")"
    [ -n "$dburl" ] && svc_obj="$(echo "$svc_obj" | jq --arg u "$dburl" '. + {url:$u}')"
    services="$(echo "$services" | jq --arg k "$svc" --argjson v "$svc_obj" '. + {($k):$v}')"
  done
  [ -z "$primary" ] && primary="$(echo "$services" | jq -r 'to_entries|map(.value.ports[]?|select(.url)|.url)|.[0] // ""')"
  jq -n --arg t "$task" --arg p "$proj" --arg wt "$wt" --arg b "$base" --arg g "$gen" \
        --arg pr "$primary" --argjson s "$services" \
    '{taskId:$t, project:$p, worktree:$wt, composeFile:$b, generated:$g, status:"up", services:$s, primaryUrl:$pr}'
}

cmd_up() {
  need docker; need jq
  local task="$1" wt="${2:-$PWD}" base proj gen manifest
  base="$(detect_compose "$wt")" || die "no compose file in $wt (set LOOP_COMPOSE_FILE, or use a plain dev server — see devops agent)"
  proj="$(proj_name "$task" "$wt")"
  gen="$ENV_DIR/$task.compose.json"
  manifest="$ENV_DIR/$task.json"

  # check-or-create: if the stack is already running, just reprint the saved manifest
  if [ -f "$manifest" ] && [ -n "$(COMPOSE_PROJECT_NAME="$proj" docker compose -f "$gen" ps -q 2>/dev/null)" ]; then
    cat "$manifest"; return
  fi

  gen_compose "$base" "$gen"
  ( cd "$wt" && COMPOSE_PROJECT_NAME="$proj" docker compose -f "$gen" up -d --wait ) 2>/dev/null \
    || ( cd "$wt" && COMPOSE_PROJECT_NAME="$proj" docker compose -f "$gen" up -d )

  build_manifest "$task" "$wt" "$proj" "$base" "$gen" | tee "$manifest"
  [ -d "$wt/.claude" ] || mkdir -p "$wt/.claude"
  cp "$manifest" "$wt/.claude/task-env.json" 2>/dev/null || true
}

cmd_ports() {
  local task="$1"; local m="$ENV_DIR/$task.json"
  [ -f "$m" ] || die "no env for task '$task' (run: task-env.sh up $task)"
  cat "$m"
}

cmd_down() {
  need docker
  local task="$1" wt="${2:-$PWD}" proj gen
  proj="$(proj_name "$task" "$wt")"
  gen="$ENV_DIR/$task.compose.json"
  [ -f "$gen" ] && COMPOSE_PROJECT_NAME="$proj" docker compose -f "$gen" down -v 2>/dev/null || true
  rm -f "$ENV_DIR/$task.json" "$gen"
  echo "task-env: torn down $task"
}

cmd_list() {
  need jq
  shopt -s nullglob
  local any=0 m t
  for m in "$ENV_DIR"/*.json; do
    [[ "$m" == *.compose.json ]] && continue
    any=1
    t="$(jq -r .taskId "$m")"
    jq -r '"• \(.taskId)  [\(.status)]  \(.primaryUrl // "-")\n    " + ([.services|to_entries[]|"\(.key):\(.value.ports[0].host)"]|join("  "))' "$m"
    [ -f "$ENV_DIR/$t.progress.md" ] && echo "    last: $(tail -n1 "$ENV_DIR/$t.progress.md")"
  done
  [ "$any" = 0 ] && echo "no loop task envs."
}

cmd_log() {  # <task> <text...> — append a timestamped progress line to the task journal
  local task="$1"; shift
  local f="$ENV_DIR/$task.progress.md"
  [ -s "$f" ] || printf '# Loop progress — %s\n\n' "$task" > "$f"
  printf -- '- [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$f"
}

cmd_progress() { local f="$ENV_DIR/$1.progress.md"; [ -f "$f" ] && cat "$f" || echo "no progress journal for '$1' yet."; }

cmd_selfcheck() {
  need jq
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  # 1. gen_compose's transform must strip the host-side `published` from every port
  cat > "$tmp/in.json" <<'JSON'
{"name":"x","services":{"web":{"image":"node","ports":[{"mode":"ingress","target":3000,"published":"3000","protocol":"tcp"}]},
"db":{"image":"postgres:16","environment":{"POSTGRES_PASSWORD":"secret","POSTGRES_DB":"app"},"ports":[{"target":5432,"published":"5432"}]}}}
JSON
  local out
  out="$(jq 'del(.name) | .services |= with_entries(.value.ports = ((.value.ports // []) | map(del(.published))))' "$tmp/in.json")"
  [ "$(echo "$out" | jq '[.services[].ports[]|has("published")]|any')" = "false" ] \
    || die "selfcheck FAIL: published port not stripped"
  [ "$(echo "$out" | jq 'has("name")')" = "false" ] || die "selfcheck FAIL: project name not removed"
  [ "$(echo "$out" | jq -r '.services.web.ports[0].target')" = "3000" ] || die "selfcheck FAIL: target port lost"
  # 2. db_url_for must build a postgres url from the service env
  echo "$out" > "$tmp/gen.json"
  local u; u="$(LOOP_ENV_DIR="$tmp" bash -c "$(declare -f db_url_for); db_url_for '$tmp/gen.json' db 54999")"
  [ "$u" = "postgres://postgres:secret@localhost:54999/app" ] || die "selfcheck FAIL: db url = '$u'"
  # 3. log appends to the task journal and progress reads it back
  LOOP_ENV_DIR="$tmp/j" "$0" log demo "PLAN — built plan; next: implement" >/dev/null
  LOOP_ENV_DIR="$tmp/j" "$0" progress demo | grep -q "PLAN — built plan" || die "selfcheck FAIL: progress journal not written/read"
  echo "task-env selfcheck: OK"
}

cmd_statedir() { echo "$ENV_DIR"; }   # one authority for per-task state (plans, manifests) — never inside a repo/worktree

case "${1:-}" in
  up)        shift; [ $# -ge 1 ] || die "usage: up <task-id> [worktree]"; cmd_up "$@" ;;
  ports)     shift; [ $# -ge 1 ] || die "usage: ports <task-id>"; cmd_ports "$@" ;;
  down)      shift; [ $# -ge 1 ] || die "usage: down <task-id> [worktree]"; cmd_down "$@" ;;
  list)      cmd_list ;;
  statedir)  cmd_statedir ;;
  log)       shift; [ $# -ge 2 ] || die "usage: log <task-id> <text...>"; cmd_log "$@" ;;
  progress)  shift; [ $# -ge 1 ] || die "usage: progress <task-id>"; cmd_progress "$@" ;;
  selfcheck) cmd_selfcheck ;;
  *) die "usage: task-env.sh up|ports|down|list|statedir|log|progress|selfcheck  (see header)";;
esac
