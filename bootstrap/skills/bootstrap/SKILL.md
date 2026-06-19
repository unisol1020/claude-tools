---
name: bootstrap
description: One command to make a repo (and a fresh machine) fully ready for this Claude Code setup. Installs and configures the required extensions if they're missing — ripgrep, CodeGraph + its MCP, graphify, and the caveman plugin — then builds the CodeGraph index, optionally builds the graphify knowledge graph, augments CLAUDE.md, and records the repo as bootstrapped so the session-start nudge stops. Use when onboarding a project or a teammate's machine, when the session-start hook says the repo isn't bootstrapped, or when the user runs /bootstrap.
---

# bootstrap — one-command project + environment setup

Run this to take a repo (and a fresh machine) from nothing to fully set up for this stack. The point: a teammate clones a repo, runs `/bootstrap`, and every extension the projects here expect is installed, configured, and indexed — no hunting for what to install or how to wire it up.

## What it sets up

- **ripgrep** (`rg`) — fast search.
- **CodeGraph** — the `@colbymchenry/codegraph` CLI + its MCP server in Claude Code, then a built index of this repo.
- **graphify** — the `graphifyy` package + the `/graphify` skill.
- **caveman** — the caveman Claude Code plugin (compressed mode + statusline badge).

Only what's missing is installed; re-running is safe.

## Steps

1. **Resolve repo + bootstrapped state.** `root = $(git rev-parse --show-toplevel 2>/dev/null || pwd)`. If `root` is already a line in `~/.claude/.bootstrapped-projects`, tell the user it's already bootstrapped and ask whether to re-run (refresh deps / re-index) or stop.

2. **Install + configure the extensions.** Run the bundled setup script — it detects what's present and installs only the gaps, idempotently:
   ```bash
   bash ~/.claude/skills/bootstrap/setup-env.sh
   ```
   Relay what it installed vs what was already there. It handles ripgrep, the CodeGraph CLI + MCP, graphify + its skill, and writes the caveman plugin into `~/.claude/settings.json`. The caveman plugin + CodeGraph MCP only surface after a **Claude Code restart** — note that for the end.

3. **Build the CodeGraph index.** If `$root/.codegraph/` doesn't exist:
   - **Large repo** (lots of files / a big monorepo)? **Ask first** — indexing can take a while and spins up workers. On confirm (or for a normal-size repo): `codegraph init "$root"`.
   - Already indexed → `codegraph sync "$root"` to catch up.

4. **Build the graphify knowledge graph (optional, heavy).** Offer to run `/graphify` on the repo — a heavier pipeline (extraction, clustering, may download models). **Ask before running**; run on confirm, skip otherwise. Never kick it off silently.

5. **Augment CLAUDE.md.** Create or update `$root/CLAUDE.md` with a short note that CodeGraph is indexed and should be reached for before grep/find on code questions (mirror the user's global convention), plus the detected stack. Don't duplicate a note that's already there.

6. **Record completion.** Append `root` as a new line to `~/.claude/.bootstrapped-projects` (create the file if missing; no duplicates). This stops the session-start nudge for this repo.

7. **Report.** What was installed, whether the index built, whether graphify ran, and: **restart Claude Code once** so the caveman plugin + CodeGraph MCP load.

## Rules

- **Idempotent + non-destructive.** Install only the gaps; back up `settings.json` / `CLAUDE.md` before editing; don't re-index a fresh index without a reason.
- **Ask before the heavy/slow steps** — indexing a large repo and running `/graphify`. Don't start them silently.
- **Keep private data local.** `~/.claude/.bootstrapped-projects` lists real repo paths; it lives under `~/.claude` and is never committed to any repo.
- **No secrets, no prod actions.** This only installs dev tooling and indexes locally.
