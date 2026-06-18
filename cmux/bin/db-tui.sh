#!/usr/bin/env bash
# db-tui — open a terminal SQL client in a right-side cmux split (falls back to the
# current terminal when not inside cmux). Recommended client: harlequin (cross-DB SQL
# IDE for the terminal); lazysql is a lighter vim-style alternative.
#
# Usage:
#   db-tui.sh                      # uses $DATABASE_URL
#   db-tui.sh postgres://u:p@host/db
#   DB_CLIENT=lazysql db-tui.sh    # force a specific client
set -euo pipefail

URL="${1:-${DATABASE_URL:-}}"
CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"

pick_client() {
  if [ -n "${DB_CLIENT:-}" ]; then command -v "$DB_CLIENT" && return 0; fi
  for c in harlequin lazysql pgcli litecli usql; do command -v "$c" >/dev/null 2>&1 && { echo "$c"; return 0; }; done
  return 1
}

client="$(pick_client || true)"
if [ -z "$client" ]; then
  cat >&2 <<'EOF'
No terminal SQL client found. Install one:
  brew install harlequin          # cross-DB SQL IDE (Postgres/SQLite/MySQL/DuckDB) — recommended
  brew install lazysql            # vim-style TUI browser (tap: jorgerojas26/lazysql)
  pipx install 'harlequin[postgres]'   # if you prefer pipx
EOF
  exit 1
fi

# Build the launch command per client.
case "$client" in
  harlequin) cmd=$([ -n "$URL" ] && echo "harlequin '$URL'" || echo "harlequin") ;;
  lazysql)   cmd=$([ -n "$URL" ] && echo "lazysql '$URL'"   || echo "lazysql")   ;;
  pgcli|litecli|usql) cmd=$([ -n "$URL" ] && echo "$client '$URL'" || echo "$client") ;;
  *)         cmd="$client" ;;
esac

# Inside cmux → open in a right-side split anchored to THIS workspace. Else run inline.
if [ -S "${CMUX_SOCKET_PATH:-/tmp/cmux.sock}" ] && [ -n "${CMUX_WORKSPACE_ID:-}" ] && [ -x "$CMUX" ]; then
  out=$("$CMUX" --json new-pane --workspace "$CMUX_WORKSPACE_ID" --type terminal --direction right --focus true 2>/dev/null)
  surf=$(printf '%s' "$out" | sed -n 's/.*"surface_ref"[^"]*"\([^"]*\)".*/\1/p' | head -1)
  if [ -n "$surf" ]; then "$CMUX" send --surface "$surf" "$cmd"$'\n'; else eval "$cmd"; fi
else
  eval "$cmd"
fi
