#!/usr/bin/env bash
# Idempotent environment setup for the claude-tools stack. Installs + configures the
# extensions the projects here expect — ripgrep, CodeGraph (+ its MCP), graphify (+ its
# skill), and the ponytail plugin — but ONLY the ones missing. Safe to re-run.
#
# Runnable two ways:
#   bash ~/.claude/skills/bootstrap/setup-env.sh     # standalone, from a terminal
#   (invoked by the /bootstrap skill)
set -uo pipefail
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
have() { command -v "$1" >/dev/null 2>&1; }
note() { printf '  %s\n' "$*"; }
ts()   { date +%Y%m%d-%H%M%S; }

echo "Setting up the claude-tools stack (installs only what's missing) ..."

# 1. ripgrep ----------------------------------------------------------------
if have rg; then note "✓ ripgrep already installed"
elif have brew; then note "installing ripgrep…"; brew install ripgrep >/dev/null && note "✓ ripgrep"
else note "✗ ripgrep missing — install Homebrew or your distro's ripgrep package"; fi

# 2. CodeGraph CLI + MCP ----------------------------------------------------
if have codegraph; then note "✓ codegraph already installed ($(codegraph --version 2>/dev/null))"
else
  note "installing @colbymchenry/codegraph…"
  if   have volta; then volta install @colbymchenry/codegraph >/dev/null 2>&1
  elif have npm;   then npm  i -g     @colbymchenry/codegraph >/dev/null 2>&1
  else note "✗ codegraph needs node/npm (or volta) — install Node first"; fi
  have codegraph && note "✓ codegraph installed" || note "✗ codegraph install failed — run: npm i -g @colbymchenry/codegraph"
fi
# Wire the CodeGraph MCP into Claude Code (non-interactive, global, auto-allow).
if have codegraph; then
  codegraph install -y >/dev/null 2>&1 && note "✓ codegraph MCP wired into Claude Code" \
    || note "… run 'codegraph install -y' manually to add the MCP"
fi

# 3. graphify (npm pkg 'graphifyy', provides the 'graphify' CLI) + its skill -
if have graphify; then note "✓ graphify already installed ($(graphify --version 2>/dev/null))"
else
  note "installing graphifyy…"
  if   have volta; then volta install graphifyy >/dev/null 2>&1
  elif have npm;   then npm  i -g     graphifyy >/dev/null 2>&1
  else note "✗ graphify needs node/npm (or volta) — install Node first"; fi
  have graphify && note "✓ graphify installed" \
    || note "… graphify CLI not on PATH after install — reopen your shell, then re-run, or: npm i -g graphifyy"
fi
# Install the graphify skill into Claude Code.
# NB: 'graphify install claude' copies the SKILL.md into ~/.claude/skills (gives the
# /graphify command). 'graphify claude install' only writes a CLAUDE.md section — no skill.
if [ -f "$CLAUDE_DIR/skills/graphify/SKILL.md" ]; then note "✓ graphify skill already installed"
elif have graphify; then
  graphify install claude >/dev/null 2>&1 && note "✓ graphify skill installed (/graphify available after restart)" \
    || note "… run 'graphify install claude' manually"
fi

# 4. ponytail plugin (merge marketplace + enable into settings.json) ---------
if have jq; then
  mkdir -p "$CLAUDE_DIR"; sj="$CLAUDE_DIR/settings.json"; [ -f "$sj" ] || echo '{}' > "$sj"
  if jq -e '.enabledPlugins["ponytail@ponytail"] == true' "$sj" >/dev/null 2>&1; then
    note "✓ ponytail plugin already enabled"
  else
    cp -p "$sj" "$sj.bak-$(ts)"
    jq '.extraKnownMarketplaces.ponytail.source = {source:"github", repo:"DietrichGebert/ponytail"}
        | .enabledPlugins = (.enabledPlugins // {})
        | .enabledPlugins["ponytail@ponytail"] = true' "$sj" > "$sj.tmp" && mv "$sj.tmp" "$sj" \
      && note "✓ ponytail marketplace + enable written to settings.json (fetched on next Claude Code start)"
  fi
else note "✗ jq needed to enable the ponytail plugin — brew install jq"; fi

echo "Done. Restart Claude Code once so the ponytail plugin + CodeGraph MCP load."
