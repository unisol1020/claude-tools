#!/bin/zsh
# cmux preferredEditor wrapper. Invoked by cmux on a Cmd-click / file-tree open of a
# readable file (terminal links, file explorer, Claude Code file mentions) because
# cmux.json has app.openSupportedFilesInCmux:false. Routes by type:
#   - images / pdf / audio / video -> cmux built-in preview, split right
#   - everything else (text/code)  -> fresh, in ONE persistent session+pane per workspace
#
# Flicker-free reuse via fresh SESSIONS (not new terminal tabs):
#   - A named fresh session "ws-<workspace>" is kept alive per workspace.
#   - First open in a workspace boots a terminal surface that runs `fresh -a ws-<id> FILE`
#     (one-time shell+editor spawn). Its pane UUID is persisted in fresh-pane-<ws>.id.
#   - Every later open, while that pane AND session are still alive, just runs
#     `fresh --cmd session open-file ws-<id> FILE` — the file appears in the live editor
#     with NO new surface, NO shell boot, NO flicker. The pane is focused so it surfaces.
#   - If pane or session died, fall back to spawning a fresh-attach surface again.
# GUI-launched: minimal PATH, so every binary is an absolute path.
EDITOR_BIN="/opt/homebrew/bin/fresh"; [ -x "$EDITOR_BIN" ] || EDITOR_BIN="/usr/local/bin/fresh"
CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"
PY="/usr/bin/python3"
SED="/usr/bin/sed"
AWK="/usr/bin/awk"
DATE="/bin/date"
SLEEP="/bin/sleep"
STAT="/usr/bin/stat"
STATE_DIR="$HOME/.config/cmux"
LOG="$STATE_DIR/open-wrapper.log"
DBG="$STATE_DIR/open-wrapper-debug.log"
dbg() { echo "$("$DATE" '+%F %T') $*" >> "$DBG"; }

# Serialize opens within one workspace. Without this, two near-simultaneous opens
# (Claude mentioning several files, a quick double Cmd-click) each read "no editor yet"
# and each spawn their OWN surface — the reported "2 files land in different surfaces".
# Under the lock the 2nd open waits, then sees the session+pane the 1st created and
# routes the file in. Atomic mkdir (no flock on macOS). A lock older than 15s is stolen
# (crashed run); after ~5s we proceed unlocked rather than stall an interactive open.
LOCK_HELD=""
# Top-level trap (NOT inside the function): zsh fires an EXIT trap set inside a function
# when that function returns, which would drop the lock before the critical section.
trap 'rm -rf "$LOCK_HELD" 2>/dev/null' EXIT INT TERM
acquire_lock() {
  local lock="$STATE_DIR/open-lock-$1.d" waited=0 age
  while ! mkdir "$lock" 2>/dev/null; do
    age=$(( $("$DATE" +%s) - $("$STAT" -f %m "$lock" 2>/dev/null || echo 0) ))
    if [ "$age" -gt 15 ]; then rm -rf "$lock" 2>/dev/null; continue; fi
    [ "$waited" -ge 50 ] && return 0
    "$SLEEP" 0.1 2>/dev/null || true
    waited=$((waited + 1))
  done
  LOCK_HELD="$lock"
}

file="$1"
[ -z "$file" ] && exit 1
dir="${file:h}"
# Launch at the GIT REPO ROOT so cmux's workspace/sidebar context stays fixed across the
# monorepo. fresh resolves the per-file LSP root via root_markers (tsconfig.json), so
# launching from the repo root does not affect type-checking or the @/ alias.
projroot="$dir"
while [ "$projroot" != "/" ] && [ ! -e "$projroot/.git" ]; do
  projroot="${projroot:h}"
done
[ "$projroot" = "/" ] && projroot="$dir"

case "${file:l}" in
  *.png|*.jpg|*.jpeg|*.gif|*.webp|*.bmp|*.tif|*.tiff|*.heic|*.heif|*.svg|*.ico|*.avif|*.pdf|*.mov|*.mp4|*.m4v|*.webm|*.mkv|*.mp3|*.wav|*.m4a|*.aac|*.flac|*.ogg)
    echo "$("$DATE" '+%F %T') PREVIEW $file" >> "$LOG"
    out=$("$CMUX" --json open "$file" --no-focus 2>/dev/null)
    surf=$(printf '%s' "$out" | "$SED" -n 's/.*"surface_ref"[^"]*"\([^"]*\)".*/\1/p' | head -1)
    if [ -n "$surf" ]; then
      "$CMUX" split-off --surface "$surf" right --focus true
    else
      "$CMUX" open "$file" --focus true
    fi
    exit 0
    ;;
esac

echo "$("$DATE" '+%F %T') FRESH $file" >> "$LOG"

tree=$("$CMUX" tree --json --id-format uuids 2>/dev/null)

active_ws=""
if [ -x "$PY" ] && [ -n "$tree" ]; then
  active_ws=$(printf '%s' "$tree" | "$PY" -c 'import sys,json;print(json.load(sys.stdin).get("active",{}).get("workspace_id",""))')
fi

# Hold the per-workspace lock across the read-state-then-spawn decision below, and
# re-read the tree after acquiring it: a concurrent open may have created the editor
# while we waited, in which case the recomputed reuse_pane/session_alive take the
# flicker-free fast path instead of spawning a second surface.
if [ -n "$active_ws" ]; then
  acquire_lock "$active_ws"
  tree=$("$CMUX" tree --json --id-format uuids 2>/dev/null)
fi

session=""
state_file=""
if [ -n "$active_ws" ]; then
  session="ws-${active_ws}"
  state_file="$STATE_DIR/fresh-pane-${active_ws}.id"
fi

# Is the persisted editor pane still alive in this workspace?
reuse_pane=""
if [ -n "$state_file" ] && [ -f "$state_file" ] && [ -n "$tree" ]; then
  saved=$(cat "$state_file" 2>/dev/null)
  if [ -n "$saved" ]; then
    alive=$(printf '%s' "$tree" | WS="$active_ws" PANE="$saved" "$PY" -c '
import sys,json,os
d=json.load(sys.stdin); ws=os.environ["WS"]; pane=os.environ["PANE"]
for w in d.get("windows",[]):
  for x in w.get("workspaces",[]):
    if x.get("id")==ws:
      for p in x.get("panes",[]):
        if p.get("id")==pane: print("yes")
')
    [ "$alive" = "yes" ] && reuse_pane="$saved"
  fi
fi

# Is the named fresh session alive?
session_alive=""
if [ -n "$session" ]; then
  session_alive=$("$EDITOR_BIN" --cmd session list 2>/dev/null | "$AWK" -v s="$session" '/^(Active sessions|Running daemons):/{f=1;next} /^[[:space:]]*$/{f=0} f && $1==s{print "1"; exit}')
fi

dbg "DECISION file=$file active_ws=${active_ws:-NONE} session=${session:-NONE} session_alive=${session_alive:-0} saved_pane=$(cat "$state_file" 2>/dev/null) reuse_pane=${reuse_pane:-NONE}"

# The fresh SESSION is the editor; a pane only displays it. Whenever the session is alive
# the file ALWAYS routes into it via `session open-file` — it never spawns a new surface/tab.
surf=""
if [ -n "$session_alive" ]; then
  echo "$("$DATE" '+%F %T') OPENFILE session=$session $file" >> "$LOG"
  "$EDITOR_BIN" --cmd session open-file "$session" "$file" >> "$LOG" 2>&1
  if [ -n "$reuse_pane" ]; then
    dbg "BRANCH=FASTPATH pane=$reuse_pane"
    "$CMUX" focus-pane --pane "$reuse_pane" 2>/dev/null
    exit 0
  fi
  dbg "BRANCH=REATTACH session alive, pane gone -> new pane"
else
  dbg "BRANCH=CREATE no live session -> new session"
  [ -n "$session" ] && "$EDITOR_BIN" --cmd session new "$session" >/dev/null 2>&1
fi

# Need a pane to display the session. Reuse the live editor pane's OWN surface when it
# survives (replace its shell — no new tab); otherwise open one right-side pane. Always a
# pane, never a stacked surface.
if [ -n "$reuse_pane" ] && [ -x "$PY" ]; then
  surf=$(printf '%s' "$tree" | PANE="$reuse_pane" "$PY" -c '
import sys,json,os
d=json.load(sys.stdin); pane=os.environ["PANE"]
for w in d.get("windows",[]):
  for x in w.get("workspaces",[]):
    for p in x.get("panes",[]):
      if p.get("id")==pane:
        ss=p.get("surfaces") or []; sel=p.get("selected_surface_ref")
        for s in ss:
          if s.get("ref")==sel or s.get("id")==sel: print(s.get("id")); sys.exit()
        if ss: print(ss[0].get("id")); sys.exit()
')
  [ -n "$surf" ] && dbg "BRANCH=REUSE-PANE-SURFACE pane=$reuse_pane surf=$surf"
fi

if [ -z "$surf" ]; then
  # Open the editor as the FAR-RIGHT pane regardless of what's focused: focus the current
  # rightmost pane first so the right-split lands at the workspace's right edge (not carving
  # up whatever was focused, e.g. the Claude pane).
  if [ -n "$active_ws" ] && [ -x "$PY" ]; then
    rightmost=$("$CMUX" --id-format uuids list-panes --workspace "$active_ws" --json 2>/dev/null | "$PY" -c '
import sys,json
d=json.load(sys.stdin); panes=d.get("panes",[])
if len(panes)>1: print(max(panes, key=lambda p:(p.get("pixel_frame") or {}).get("x",0))["id"])
')
    [ -n "$rightmost" ] && "$CMUX" focus-pane --pane "$rightmost" --workspace "$active_ws" >/dev/null 2>&1
  fi
  if [ -n "$active_ws" ]; then
    dbg "BRANCH=NEW-PANE ws=$active_ws (far-right)"
    out=$("$CMUX" --json --id-format uuids new-pane --workspace "$active_ws" --type terminal --direction right --focus true 2>>"$DBG")
  else
    dbg "BRANCH=NEW-PANE-nows"
    out=$("$CMUX" --json --id-format uuids new-pane --type terminal --direction right --focus true 2>>"$DBG")
  fi
  dbg "CREATE_OUT=$out"
  surf=$(printf '%s' "$out" | "$SED" -n 's/.*"surface_id"[^"]*"\([^"]*\)".*/\1/p' | head -1)
  [ -z "$surf" ] && surf=$(printf '%s' "$out" | "$SED" -n 's/.*"surface_ref"[^"]*"\([^"]*\)".*/\1/p' | head -1)
fi

# Post-create placement + sizing for a freshly-made editor pane (skipped when a pane was reused).
if [ -n "$out" ] && [ -n "$surf" ] && [ -n "$active_ws" ] && [ -x "$PY" ]; then
  "$SLEEP" 0.2 2>/dev/null || true
  # Safety net: if focusing the rightmost didn't take and the editor isn't rightmost, swap it there.
  swaptarget=$("$CMUX" --id-format uuids list-panes --workspace "$active_ws" --json 2>/dev/null | ESURF="$surf" "$PY" -c '
import sys,json,os
d=json.load(sys.stdin); es=os.environ["ESURF"]; panes=d.get("panes",[])
mine=next((p for p in panes if es in (p.get("surface_ids") or [])), None)
if not mine or len(panes)<2: sys.exit()
rightmost=max(panes, key=lambda p:(p.get("pixel_frame") or {}).get("x",0))
if mine["id"]!=rightmost["id"]: print(mine["id"], rightmost["id"])
')
  if [ -n "$swaptarget" ]; then
    mp="${swaptarget%% *}"; rtp="${swaptarget##* }"
    dbg "SWAP editor $mp -> rightmost $rtp"
    "$CMUX" swap-pane --pane "$mp" --target-pane "$rtp" --workspace "$active_ws" --focus false >/dev/null 2>>"$DBG"
    "$SLEEP" 0.2 2>/dev/null || true
  fi
  # The editor pane is now whichever pane holds $surf (rightmost). Persist it for reuse and
  # size it to ~35% of the workspace width by driving its LEFT divider (eats/feeds its left
  # neighbor — the old rightmost pane — never the leftmost Claude pane). Exact pixels.
  plan=$("$CMUX" --id-format uuids list-panes --workspace "$active_ws" --json 2>/dev/null | ESURF="$surf" "$PY" -c '
import sys,json,os
d=json.load(sys.stdin); es=os.environ["ESURF"]
tot=(d.get("container_frame") or {}).get("width"); panes=d.get("panes",[])
me=next((p for p in panes if es in (p.get("surface_ids") or [])), None)
if not me: sys.exit()
print("PANE", me["id"])
if not tot: sys.exit()
mx=me["pixel_frame"]["x"]; mw=me["pixel_frame"]["width"]
need=round(0.35*tot - mw)
if abs(need)<8: sys.exit()
left=[p for p in panes if (p.get("pixel_frame") or {}).get("x",1e9)<mx]
left.sort(key=lambda p:p["pixel_frame"]["x"])
if not left: sys.exit()
if need>0: print("RESIZE", me["id"], "-L", need)
else: print("RESIZE", left[-1]["id"], "-R", -need)
')
  epane=$(printf '%s' "$plan" | "$AWK" '/^PANE/{print $2; exit}')
  [ -n "$epane" ] && [ -n "$state_file" ] && printf '%s' "$epane" > "$state_file"
  rline=$(printf '%s' "$plan" | "$AWK" '/^RESIZE/{print $2, $3, $4; exit}')
  if [ -n "$rline" ]; then
    rp="${rline%% *}"; rest="${rline#* }"; flag="${rest%% *}"; amt="${rest##* }"
    dbg "RESIZE editor->35% pane=$rp $flag $amt"
    "$CMUX" resize-pane --pane "$rp" --workspace "$active_ws" "$flag" --amount "$amt" >/dev/null 2>>"$DBG"
  fi
fi

# `exec` so fresh replaces the shell (no lingering prompt). Attach the per-workspace
# session when we have one; otherwise plain fresh.
if [ -n "$session" ]; then
  launch="exec $EDITOR_BIN -a '$session' '$file'"
else
  launch="cd '$projroot' && exec $EDITOR_BIN '$file'"
fi
if [ -n "$surf" ]; then
  "$CMUX" send --surface "$surf" "$launch"$'\n'
else
  "$CMUX" send "$launch"$'\n'
fi
