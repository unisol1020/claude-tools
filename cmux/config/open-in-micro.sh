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
STATE_DIR="$HOME/.config/cmux"
LOG="$STATE_DIR/open-wrapper.log"

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
  session_alive=$("$EDITOR_BIN" --cmd session list 2>/dev/null | "$AWK" -v s="$session" '/^Active sessions:/{f=1;next} /^[[:space:]]*$/{f=0} f && $1==s{print "1"; exit}')
fi

# Flicker-free fast path: live pane + live session -> route the file into the running editor.
if [ -n "$reuse_pane" ] && [ -n "$session_alive" ]; then
  echo "$("$DATE" '+%F %T') OPENFILE session=$session $file" >> "$LOG"
  "$EDITOR_BIN" --cmd session open-file "$session" "$file" >> "$LOG" 2>&1
  "$CMUX" focus-pane --pane "$reuse_pane" 2>/dev/null
  exit 0
fi

# Otherwise we need a surface running `fresh -a <session>`. Pre-create the session
# (detached server) so the attach inside the terminal always finds it.
[ -n "$session" ] && [ -z "$session_alive" ] && "$EDITOR_BIN" --cmd session new "$session" >/dev/null 2>&1

if [ -n "$reuse_pane" ]; then
  out=$("$CMUX" --json --id-format uuids new-surface --pane "$reuse_pane" --type terminal --working-directory "$projroot" --focus true 2>/dev/null)
elif [ -n "$active_ws" ]; then
  out=$("$CMUX" --json --id-format uuids new-pane --workspace "$active_ws" --type terminal --direction right --focus true 2>/dev/null)
else
  out=$("$CMUX" --json --id-format uuids new-pane --type terminal --direction right --focus true 2>/dev/null)
fi

surf=$(printf '%s' "$out" | "$SED" -n 's/.*"surface_id"[^"]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$surf" ] && surf=$(printf '%s' "$out" | "$SED" -n 's/.*"surface_ref"[^"]*"\([^"]*\)".*/\1/p' | head -1)

if [ -z "$reuse_pane" ] && [ -n "$surf" ] && [ -n "$state_file" ] && [ -x "$PY" ]; then
  newtree=$("$CMUX" tree --json --id-format uuids 2>/dev/null)
  pane_uuid=$(printf '%s' "$newtree" | SURF="$surf" "$PY" -c '
import sys,json,os
d=json.load(sys.stdin); surf=os.environ["SURF"]
for w in d.get("windows",[]):
  for x in w.get("workspaces",[]):
    for p in x.get("panes",[]):
      for s in p.get("surfaces",[]):
        if s.get("id")==surf: print(p.get("id","")); sys.exit()
')
  [ -n "$pane_uuid" ] && printf '%s' "$pane_uuid" > "$state_file"
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
