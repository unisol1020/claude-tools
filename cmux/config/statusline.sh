#!/usr/bin/env bash
# Claude Code statusline — colored text segments divided by |:
#   📁 dir | ⎇ branch | ⇡push ⇣pull | ±files +adds -dels | context% | model + 1M badge | ⬡ codegraph | caveman badge
input=$(cat)

dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
[ -z "$dir" ] && dir="$PWD"
cd "$dir" 2>/dev/null || true
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)

R=$'\033[0m'
SEP=$' \033[38;5;240m|\033[0m '   # gray divider
# fg colors
C_DIR=$'\033[38;5;39m'; C_BR=$'\033[38;5;213m'; C_PUSH=$'\033[38;5;42m'
C_PULL=$'\033[38;5;45m'; C_SYNC=$'\033[38;5;108m'; C_FILE=$'\033[38;5;214m'
C_ADD=$'\033[38;5;42m'; C_DEL=$'\033[38;5;203m'; C_CLEAN=$'\033[38;5;108m'; C_MOD=$'\033[38;5;245m'
C_CG=$'\033[38;5;79m'; C_CG_OFF=$'\033[38;5;240m'; C_CG_WARN=$'\033[38;5;208m'  # codegraph index
C_1M=$'\033[38;5;220m'  # 1M-context model badge

segs=()
segs+=("${C_DIR}$(basename "$dir")${R}")

branch=$(git symbolic-ref --short -q HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
if [ -n "$branch" ]; then
  segs+=("${C_BR}⎇ ${branch}${R}")

  ab=$(git rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
  if [ -n "$ab" ]; then
    behind=$(printf '%s' "$ab" | awk '{print $1}'); ahead=$(printf '%s' "$ab" | awk '{print $2}')
    up="${C_PUSH}⇡${R}";   [ "${ahead:-0}"  -gt 0 ] 2>/dev/null && up="${C_PUSH}⇡${ahead}${R}"
    down="${C_PULL}⇣${R}"; [ "${behind:-0}" -gt 0 ] 2>/dev/null && down="${C_PULL}⇣${behind}${R}"
    segs+=("${up} ${down}")
  fi

  files=$(git status --porcelain 2>/dev/null | grep -c .)
  shortstat=$(git diff --shortstat 2>/dev/null)
  adds=$(printf '%s' "$shortstat" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
  dels=$(printf '%s' "$shortstat" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')
  if [ "${files:-0}" -gt 0 ] 2>/dev/null || [ -n "$adds" ] || [ -n "$dels" ]; then
    chg="${C_FILE}±${files}${R}"
    [ -n "$adds" ] && chg="${chg} ${C_ADD}+${adds}${R}"
    [ -n "$dels" ] && chg="${chg} ${C_DEL}-${dels}${R}"
    segs+=("$chg")
  else
    segs+=("${C_CLEAN}✓ clean${R}")
  fi
fi

# context usage — parse the live transcript (matches /context). cheap: grep|tail -1
# grabs the last main-chain assistant message, so no whole-file jq slurp.
tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
if [ -n "$tp" ] && [ -f "$tp" ]; then
  last_usage=$(grep '"usage"' "$tp" 2>/dev/null | grep -v '"isSidechain":true' | tail -1)
  used=$(printf '%s' "$last_usage" | jq -r '(.message.usage // {}) | ((.input_tokens//0)+(.cache_read_input_tokens//0)+(.cache_creation_input_tokens//0))' 2>/dev/null)
  if [ -n "$used" ] && [ "$used" -gt 0 ] 2>/dev/null; then
    case "$(printf '%s' "$input" | jq -r '.model.id // empty' 2>/dev/null)" in
      *'[1m]'*|*1M*) win=1000000; winlbl="1M" ;;
      *)            win=200000;  winlbl="200k" ;;
    esac
    pct=$(( used * 100 / win ))
    usedk=$(( (used + 500) / 1000 ))
    if   [ "$pct" -ge 80 ]; then C_CTX=$'\033[38;5;203m'   # red
    elif [ "$pct" -ge 50 ]; then C_CTX=$'\033[38;5;214m'   # amber
    else                         C_CTX=$'\033[38;5;42m'    # green
    fi
    segs+=("${C_CTX}${pct}%${R}")
  fi
fi

if [ -n "$model" ]; then
  mname=${model%% (*}
  case "$(printf '%s' "$input" | jq -r '.model.id // empty' 2>/dev/null)" in
    *'[1m]'*|*1M*) mname="${mname} ${C_1M}1M${R}${C_MOD}" ;;
  esac
  segs+=("${C_MOD}${mname}${R}")
fi

# codegraph index status — trailing (sits near the caveman badge so it doesn't
# crowd the git/context segments). cheap: only invoke the binary when an index db
# exists, so non-indexed repos stay instant. perl alarm = 2s safety timeout (no `timeout` on macOS).
if command -v codegraph >/dev/null 2>&1; then
  cg_root=$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$dir")
  if [ -f "$cg_root/.codegraph/codegraph.db" ]; then
    cg_json=$(perl -e 'alarm 2; exec @ARGV' codegraph status --json 2>/dev/null)
    cg=$(printf '%s' "$cg_json" | jq -r '
      if .initialized != true then "OFF||"
      else
        (((.pendingChanges.added // 0) + (.pendingChanges.modified // 0) + (.pendingChanges.removed // 0))) as $p |
        (if (.index.reindexRecommended // false) then "REINDEX" elif $p > 0 then "STALE" else "OK" end) as $s |
        "\($s)|\(.fileCount // 0)f \(.nodeCount // 0)n|\($p)"
      end' 2>/dev/null)
    cg_state=${cg%%|*}; cg_rest=${cg#*|}; cg_stat=${cg_rest%%|*}; cg_pend=${cg_rest#*|}
    case "$cg_state" in
      OK)      segs+=("${C_CG}⬡ ✓${R}") ;;
      STALE)   segs+=("${C_CG_WARN}⬡ ⚠${cg_pend}${R}") ;;
      REINDEX) segs+=("${C_CG_WARN}⬡ reindex${R}") ;;
      *)       segs+=("${C_CG_OFF}⬡ off${R}") ;;
    esac
  else
    segs+=("${C_CG_OFF}⬡ —${R}")
  fi
fi

# join segments with the divider
out=""
for i in "${!segs[@]}"; do
  [ "$i" -eq 0 ] && out="${segs[$i]}" || out="${out}${SEP}${segs[$i]}"
done

# caveman token badge (own colors), trailing. Path globbed so it survives plugin updates.
badge_sh=$(ls "$HOME"/.claude/plugins/cache/caveman/caveman/*/src/hooks/caveman-statusline.sh 2>/dev/null | head -1)
if [ -n "$badge_sh" ] && [ -f "$badge_sh" ]; then
  cm=$(printf '%s' "$input" | bash "$badge_sh" 2>/dev/null)
  [ -n "$cm" ] && out="${out}  ${cm}"
fi

printf '%s' "$out"
