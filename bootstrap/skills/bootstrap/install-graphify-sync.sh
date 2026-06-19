#!/bin/sh
# Install the graphify per-commit auto-sync into a repo's .claude/.
# Idempotent + non-destructive. Arg $1 = repo root (default: git toplevel or pwd).
#
# Effect: after every `git commit`, a silent, zero-token AST pass refreshes
# graphify-out/graph.json from the commit's changed code files. The model is
# never involved. Requires graphify already set up and a graph already built
# (graphify-out/graph.json present).
set -e
ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
TPL="$HOME/.claude/skills/bootstrap/templates"
DEST="$ROOT/.claude"
mkdir -p "$DEST"

cp "$TPL/graphify-sync.py" "$DEST/graphify-sync.py"
cp "$TPL/graphify-sync.sh" "$DEST/graphify-sync.sh"
chmod +x "$DEST/graphify-sync.sh"

SETTINGS="$DEST/settings.local.json"
[ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"
[ -f "$SETTINGS.bak" ] || cp "$SETTINGS" "$SETTINGS.bak"

python3 - "$SETTINGS" <<'PY'
import json, sys
p = sys.argv[1]
try:
    cfg = json.load(open(p))
except Exception:
    cfg = {}
cmd = ('input=$(cat); cmd=$(printf \'%s\' "$input" | jq -r \'.tool_input.command // ""\'); '
       'if printf \'%s\' "$cmd" | grep -qE \'git[[:space:]]+commit\'; then '
       '( sh "${CLAUDE_PROJECT_DIR:-.}/.claude/graphify-sync.sh" >/dev/null 2>&1 & ); fi; exit 0')
hooks = cfg.setdefault("hooks", {})
post = hooks.setdefault("PostToolUse", [])
# idempotent: skip if a graphify-sync hook is already wired
already = any("graphify-sync.sh" in (h.get("command", ""))
             for entry in post for h in entry.get("hooks", []))
if not already:
    post.append({
        "matcher": "Bash",
        "hooks": [{
            "type": "command",
            "command": cmd,
            "statusMessage": "Refreshing graphify graph (incremental, no LLM)",
        }],
    })
    json.dump(cfg, open(p, "w"), indent=2)
    print("hook added")
else:
    print("hook already present")
PY

# Keep .claude personal unless the repo already tracks it.
if git -C "$ROOT" check-ignore -q .claude 2>/dev/null; then
    :
elif [ -f "$ROOT/.gitignore" ] && ! grep -qE '(^|/)\.claude/?$' "$ROOT/.gitignore" 2>/dev/null; then
    echo "NOTE: .claude/ is not gitignored in this repo — the sync files would be committed."
    echo "      Add '.claude/' to .gitignore to keep them personal (recommended)."
fi

echo "graphify per-commit sync installed in $DEST/"
