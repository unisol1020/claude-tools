# claude-tools

A collection of shareable tools for **Claude Code** — drop-in agents and skills that work in any local project. Install the whole set, or just the one you want, by sending this README (or a tool's README) to Claude Code and saying *"install this"*.

## Tools

| Tool | What it does | Install by link |
|------|--------------|-----------------|
| [**qa**](qa/README.md) | A `manual-qa` agent that drives a real browser to verify a feature *actually works* (functional) or *matches the design* (Figma / pixel-perfect). Remembers per-project URL + login + DB, asks once. | *"install this: https://github.com/unisol1020/claude-tools/blob/main/qa/README.md"* |
| [**tickets**](tickets/README.md) | A `ticket` skill that creates **human-readable** Linear / Jira tickets (not AI slop) — repro + verification + where the problem is, pulls Figma/design links from the chat, posts test results as a comment. | *"install this: https://github.com/unisol1020/claude-tools/blob/main/tickets/README.md"* |
| [**cmux**](cmux/README.md) | A full **cmux + Ghostty + Claude Code** environment, 1:1 — glass terminal (Catppuccin, transparent/blurred), the `fresh` editor + flicker-free file-open routing, the colored statusline, plus a `db-tui` terminal SQL-client launcher. Backs up before writing; macOS only. | *"install this: https://github.com/unisol1020/claude-tools/blob/main/cmux/README.md"* |
| [**bootstrap**](bootstrap/README.md) | A `/bootstrap` skill — one command that installs + configures the required extensions if missing (ripgrep, CodeGraph + MCP, graphify, the ponytail plugin), builds the CodeGraph index, offers `/graphify`, and records the repo. For onboarding teammates so they don't hunt for what to install. | *"install this: https://github.com/unisol1020/claude-tools/blob/main/bootstrap/README.md"* |

Each tool's README has its own self-install block, so you can install them independently.

## Install everything — just send this README to Claude Code

You don't run anything. Paste this file (or its URL) into **Claude Code** and say *"install this"*.

> **🤖 Claude Code — if a user sent you this README, install every tool in this repo now. Do not ask setup questions (each tool gathers its own per-project setup on first use, not at install). Steps:**
>
> 1. **Preflight.** Confirm `git` and the `claude` CLI are on PATH. If either is missing, stop and tell the user to install it first.
> 2. **Clone (idempotent):**
>    ```bash
>    git clone https://github.com/unisol1020/claude-tools.git ~/.claude-tools 2>/dev/null \
>      || git -C ~/.claude-tools pull --ff-only
>    ```
> 3. **Run every tool's installer:**
>    ```bash
>    for f in ~/.claude-tools/*/install.sh; do echo "== $f =="; bash "$f"; done
>    ```
>    Each installer symlinks its agent/skill into `~/.claude/` (so `git pull` updates everything) and registers or checks for the MCP it needs.
> 4. **Verify:** `ls -la ~/.claude/agents ~/.claude/skills` shows the symlinks pointing into `~/.claude-tools/*`.
> 5. **Report back to the user** — confirm what installed (claude-qa, claude-tickets), tell them to **restart Claude Code once** so agents / skills / MCP tools load, then summarize each tool in a line or two (paraphrase the per-tool READMEs; keep it short).
>
> Update later with `git -C ~/.claude-tools pull` (symlinks pick it up). Uninstall: see each tool's README, or the bottom of this file.

Requirements: [Claude Code](https://claude.com/claude-code), git, and Node.js (for the tools that use an `npx` MCP, e.g. claude-qa's Playwright). Per-tool requirements are listed in each tool's README.

### Manual install (if you'd rather)

```bash
git clone https://github.com/unisol1020/claude-tools.git ~/.claude-tools
for f in ~/.claude-tools/*/install.sh; do bash "$f"; done
```
Then restart Claude Code.

## Adding a new tool to this repo

Each tool is a top-level directory with its own `README.md` (including a `🤖`-prefixed self-install block), an executable `install.sh` that symlinks its pieces into `~/.claude/`, and a `skills/` and/or `agents/` directory. Mirror an existing tool's layout and the repo-level installer loop above will pick it up automatically.

## Uninstall

Run each tool's uninstall (see its README), then optionally remove the clone:

```bash
rm -rf ~/.claude-tools
```
