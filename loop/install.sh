#!/usr/bin/env bash
# claude-loop installer — symlinks the loop-engine + investigator skills, the devops
# agent, and the task-env helper into ~/.claude and ~/.local/bin. Re-runnable; symlinks
# mean `git pull` updates everything automatically.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
BIN_DIR="$HOME/.local/bin"

mkdir -p "$CLAUDE_DIR/agents" "$CLAUDE_DIR/skills" "$BIN_DIR"

# rm the target first: ln -sfn nests a link *inside* a pre-existing real directory
link() { rm -rf "$2"; ln -s "$1" "$2"; echo "  linked $(basename "$2")"; }

echo "Installing claude-loop into $CLAUDE_DIR ..."
link "$DIR/agents/devops.md"          "$CLAUDE_DIR/agents/devops.md"
link "$DIR/skills/loop-engine"        "$CLAUDE_DIR/skills/loop-engine"
link "$DIR/skills/investigator"       "$CLAUDE_DIR/skills/investigator"
chmod +x "$DIR/bin/task-env.sh"
link "$DIR/bin/task-env.sh"           "$BIN_DIR/task-env"

echo "Checking dependencies the loop relies on ..."
dep() { command -v "$1" >/dev/null 2>&1 && echo "  ✓ $1" || echo "  ✗ $1 — $2"; }
dep docker "per-task isolated stacks need Docker (brew install --cask docker)"
dep jq     "task-env parses compose via jq (brew install jq)"
dep gh     "the outer loop opens/polls PRs via the GitHub CLI (brew install gh)"
dep cmux   "the investigator fans out into cmux surfaces (brew install --cask cmux; macOS)"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "  ⚠ $BIN_DIR is not on PATH — add it so 'task-env' resolves";; esac

cat <<'DONE'

Done. Next:
  1. Restart Claude Code once so the skills + devops agent load.
  2. Reuses the rest of claude-tools — make sure these are installed too:
       • qa/      (manual-qa + qa-run)   — the loop's QA step
       • tickets/ (ticket skill)         — find/create the Linear ticket
     Plus a connected tracker MCP (Linear or Jira), and Claude Code's built-in /loop (PR-comment polling).
  3. Use it:
       "get 10 tickets from Linear and check them"   → runs the investigator
       "take this task and run the loop: <task + constraints>"   → runs loop-engine directly
     Toggle options per run: add "qa=off" and/or "poll=off".
     Inspect live task envs any time:  task-env list   ·   task-env ports <task-id>

Requirements: Docker + jq (per-task envs), gh (PRs), cmux (macOS, fan-out), a Linear/Jira MCP.
Optional: any other MCP (GitHub, Figma, Sentry, Supabase/Postgres, Slack, …) — the loop uses what's connected.
DONE
