#!/bin/zsh
# cmux preferredEditor wrapper. Invoked by cmux on a Cmd-click / file-tree open of a
# readable file (terminal links, file explorer, Claude Code file mentions) because
# cmux.json has app.openSupportedFilesInCmux:false. Routes by type:
#   - images / pdf / audio / video -> cmux built-in preview, split right
#   - everything else (text/code)  -> Cursor, with the file's git repo root opened as the
#     workspace folder (so it opens as a project, not a lone file). Cursor reuses an existing
#     window already rooted at that folder, else opens a new one.
# GUI-launched: minimal PATH, so binaries are absolute paths.
CURSOR="/usr/local/bin/cursor"
CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"
SED="/usr/bin/sed"
DATE="/bin/date"
LOG="$HOME/.config/cmux/open-wrapper.log"

file="$1"
[ -z "$file" ] && exit 1
dir="${file:h}"

# Walk up to the nearest .git to use as the workspace root; fall back to the file's dir.
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

echo "$("$DATE" '+%F %T') CURSOR root=$projroot $file" >> "$LOG"
exec "$CURSOR" "$projroot" "$file"
