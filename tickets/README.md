# claude-tickets

A **Claude Code** skill that creates **Linear or Jira tickets that read like a human wrote them** — short, specific, scannable — instead of the wall-of-bullets AI slop nobody can actually read.

Ask in plain words. The skill:

- **Detects the tracker per project** — Linear or Jira — from the connected MCP and repo signals (e.g. `ABC-123` branch/commit ids), and remembers it. Asks once which **team / project** to file under.
- **Bugs *and* new features, written for the tester who picks it up.** A **bug** gets *what's happening*, **where it lives**, **steps to reproduce**, and how to verify the fix. A **feature** gets *what it does / the problem it solves*, **where to find it** (the page/screen/flow + how to get there), the **design**, and concrete **how-to-test** steps with expected results. Only the sections that apply; no filler, no "comprehensive solution".
- **Pulls design context from the chat** — any **Figma**, Claude/v0/preview, or screenshot link shared in the conversation goes straight onto the ticket as an attachment/reference.
- **Enriches from any connected MCP** — uses whatever useful MCP you have, only when it's relevant: **Figma** (renders the actual frame + design tokens), **Sentry** (real error + stack frames), **Slack** (the originating thread), **GitHub** (the related PR/commit), PostHog/Grafana/Supabase (one concrete metric), Notion/Drive (the linked spec). Not connected or not relevant → skipped silently.
- **Posts test results as a comment** — the latest qa-run / test / CI result (and any long Sentry trace or log) is summarized human-readably in a **comment**, so the description stays clean.
- **Confirms the draft before creating** (unless you say "just create it"), so you get the last word.

It runs in the **main thread** because it reads the live conversation and asks you the occasional question — there's no subagent and no browser.

## What you get

| Piece | Type | Role |
|-------|------|------|
| `skills/ticket/` | skill | detect tracker → map team/project (once) → draft a human-readable ticket from the chat → create it → comment test results |

## Install — just send this README to Claude Code

You don't run anything. Paste this file (or its URL) into **Claude Code** and say *"install this"*.

> **🤖 Claude Code — if a user sent you this README, install the skill now. Do not ask for tracker/team details (those are gathered per-project on the first ticket, not at install). Steps:**
>
> 1. **Preflight.** Confirm `git` and the `claude` CLI are on PATH. If missing, stop and tell the user to install them.
> 2. **Clone (idempotent):**
>    ```bash
>    git clone https://github.com/unisol1020/claude-tools.git ~/.claude-tools 2>/dev/null \
>      || git -C ~/.claude-tools pull --ff-only
>    ```
> 3. **Run the installer:**
>    ```bash
>    bash ~/.claude-tools/tickets/install.sh
>    ```
>    It symlinks the `ticket` skill into `~/.claude/skills/` and checks whether a Linear or Atlassian (Jira) MCP is connected.
> 4. **Verify:** `ls -la ~/.claude/skills/ticket` is a symlink into `~/.claude-tools/tickets`.
> 5. **Report back to the user** — confirm it's installed, then explain briefly (paraphrase, keep it short):
>
>    > ✅ **Installed.** Restart Claude Code once so the skill loads.
>    >
>    > **How to use it — just ask, no commands:**
>    > 1. Connect a **Linear** or **Atlassian (Jira)** MCP if you haven't (claude.ai integrations, or `claude mcp add`).
>    > 2. Say what to file, in plain words: *"create a ticket for this bug"*, *"file a Linear issue for the discount bug we found"*, *"open a Jira ticket: add CSV export to reports"* — or `/ticket`.
>    > 3. **First time in a project** I ask once which tracker + which team/project to use, then remember it in `.claude/tickets.local.json`.
>    > 4. I draft a **short, human-readable** ticket from our conversation — what's happening, where the problem is, repro steps, and how to verify — and show it to you before creating.
>    > 5. Any **Figma / design / screenshot** links from our chat get attached to the ticket; the latest **test results** go on as a comment.
>    >
>    > Try: *"create a ticket for the bug we just found"*.
>
> Update later with `git -C ~/.claude-tools pull` (the symlink picks it up). Uninstall: see the bottom of this file.

Requirements: [Claude Code](https://claude.com/claude-code), git, and a connected **Linear** or **Atlassian (Jira)** MCP.

### Manual install (if you'd rather)

```bash
git clone https://github.com/unisol1020/claude-tools.git ~/.claude-tools
~/.claude-tools/tickets/install.sh
```
Then restart Claude Code.

## Use it (in any project)

1. Make sure a **Linear** or **Atlassian (Jira)** MCP is connected.
2. Ask Claude Code, in plain words:
   - *"create a ticket for this bug"* · *"file a Linear issue for the checkout discount bug"* · *"open a Jira ticket to add CSV export to the reports page"* · *"log these three issues as separate tickets"*
3. **First run in that project**, the skill detects the tracker and asks **which team / project** to file under (Linear) or **which project + issue type** (Jira), then remembers it.
4. It drafts the ticket from the conversation, shows you the draft, and on your OK creates it — attaching any design links and posting the latest test results as a comment.

## Why it doesn't read like AI slop

The skill is rule-bound to:

- a **title that says the actual thing** (≤ ~70 chars) — the broken behavior or the outcome, not "Implement a comprehensive solution for…";
- **plain, direct voice** — present tense, like a message to a teammate;
- **no filler** — banned: *comprehensive / robust / seamless / leverage*, emoji spam, throat-clearing;
- **specifics** — real file paths, symbols, URLs, numbers, never "the relevant module";
- **short over complete-looking** — only the sections with real content; a small bug is a few lines;
- **one problem per ticket** — multi-part requests split into multiple tickets;
- **evidence in a comment** — full logs / test output go on a comment, keeping the description scannable.

## Per-project memory

Your tracker + team/project mapping is stored in `<project>/.claude/tickets.local.json` (see `templates/tickets.local.json.example`). It holds **no secrets**, so a team can commit it as `.claude/tickets.json` to share the mapping (the skill reads both; `tickets.local.json` wins). Change your mind by editing the file.

## Trackers & tools

- **Linear** — via any connected Linear MCP (`list_teams` / `list_projects` / `save_issue` / `save_comment` / `create_attachment`). Tool names are detected live each session, so MCP version changes don't break the skill.
- **Jira** — via the **Atlassian** MCP. On first use the skill walks you through authentication, then files under your chosen site + project + issue type.

## Uninstall

```bash
rm ~/.claude/skills/ticket
rm -rf ~/.claude-tools   # only if nothing else in this repo is installed
```
