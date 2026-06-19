#!/bin/sh
# Refresh this repo's graphify graph from the latest commit's changed code files.
# No LLM, no tokens. Installed by /bootstrap, called by the PostToolUse hook.
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$ROOT" || exit 0
[ -f graphify-out/graph.json ] || exit 0
PY=$(cat graphify-out/.graphify_python 2>/dev/null)
[ -x "$PY" ] || PY=$(command -v python3)
[ -n "$PY" ] || exit 0
"$PY" .claude/graphify-sync.py >> .claude/graphify-sync.log 2>&1 || true
exit 0
