---
name: investigator
description: Morning conductor for the loop engine. Say "get N tickets from Linear and check them" (or /investigator) and it pulls that many tickets, investigates each against THIS codebase, and triages them into a checkbox list — what Claude Code can confidently run end-to-end in the loop, what's better skipped / done separately (with why), and which are support/research questions answerable without coding. You tick which to start; on your confirmation it asks once whether to disable the tester (QA) or the PR-comment poll, then fans out fully autonomously — one git worktree + one cmux surface per chosen ticket, each running the loop-engine. Runs in the MAIN thread (it asks you questions and reads your Linear). Use on "get/grab/pull N tickets and check/run them", "morning triage", or /investigator.
---

# investigator — pull tickets, triage, fan out the loop

You (the **main thread**) turn "get N tickets from Linear and check them" into a reviewed, autonomous batch. You investigate first, hand back a **checkbox triage** for the user to approve, then spawn one loop-engine run per chosen ticket. You ask the questions; the spawned runs do the work unattended.

## Step 1 — Figure out where tickets come from (buy context)
- **Resolve project + tracker.** `root = git rev-parse --show-toplevel`. Read `<root>/.claude/tickets.json` / `tickets.local.json` (the `ticket` skill's config) for the **tracker (Linear or Jira)** + team/project. If absent, detect which tracker MCP is connected and (once) ask team/project — the same gate the `ticket` skill uses; reuse its saved mapping, don't re-ask. Discover connected MCPs live (`claude mcp list` + this session's deferred-tool list) and load tools with **ToolSearch** before calling — names change between sessions.
- **Decide the source filter.** Default = tickets **assigned to the current user** in that team/project, in an actionable state (Triage / Todo / Backlog / current sprint or cycle), ordered by priority. If the user named a source ("from the current cycle", "in Triage", "the web backlog"), use it. Ask only if genuinely ambiguous.
- **Pull N.** Use the tracker's list tool (Linear `list_issues`, or the Jira equivalent) with that filter, limit = N (default 10). For each, fetch the full issue (Linear `get_issue` / Jira get-issue) for the description + acceptance criteria + links.

## Step 2 — Investigate + triage each ticket against THIS codebase
For each ticket, spend real effort deciding which bucket it's in — look at the repo (CodeGraph if indexed, else search), the ticket's clarity, scope, and dependencies. Bucket it:

1. **✅ Can run in the loop** — well-specified, scoped to this codebase, has (or implies) clear acceptance criteria, and is a change Claude Code can implement + QA + PR autonomously. Note the entry point (files/area) in one line.
2. **⏭️ Better to skip / do separately** — too large or vague, needs a product/human decision, spans systems or external services, blocked, or risky to do unattended. Give the one-line reason.
3. **❓ Investigation only (no coding)** — really a question/research/support ask. The loop can *answer* it (investigate + post findings to the ticket) without writing code.

Lean on any **connected MCP** that sharpens the call (installed + relevant only, never invent): **Sentry** for whether a bug is real/severe and where it fires, **GitHub** for recent changes in the area, **Figma** for whether a design actually exists (a feature with no design often belongs in "skip / do separately"), the **DB MCP** (Supabase/Postgres) for data questions that are really investigation-only, **Slack/Notion** for the thread behind a vague ticket. Discover what's connected this session and use it where it helps.

Do the investigation in parallel where it helps (spawn read-only Explore agents per ticket), but **you** produce the final triage.

## Step 3 — Hand back the checkbox list, get the user's pick
Present a scannable, grouped checklist. Pre-tick ✅; leave ⏭️ unticked; list ❓ separately. One line each: ticket id + title + the reason/entry point.

```
RUN IN LOOP (code)
- [x] ENG-123  Checkout total ignores discount code      → src/checkout/total.ts, clear repro
- [x] ENG-130  Add CSV export to reports page            → reports route, design linked
SKIP / DO SEPARATELY
- [ ] ENG-141  "Rework billing"                           → too broad, needs product scoping
- [ ] ENG-145  Upgrade Postgres major version            → infra/ops, risky unattended
INVESTIGATE ONLY (no code)
- [ ] ENG-150  Why are webhook retries spiking?           → answer from logs/code, no change
```
Ask the user to **toggle which to start** (they may tick/untick any). Wait for their confirmation — don't launch anything yet.

## Step 4 — One option gate (after they confirm the picks)
Both loop options are ON by default. Ask **once**, applied to this batch (AskUserQuestion, two toggles):
- **Tester (manual QA)** — leave ON, or disable for this batch?
- **PR-comment polling** (the 5-min wait-for-reviewer loop) — leave ON, or disable?

Record `qa=on|off` and `poll=on|off` for the launch.

## Step 5 — Fan out, fully autonomous
For each **ticked code ticket**, create its isolation and spawn a loop-engine run:
```bash
TASK="<ticket-key-lowercased>"; WT="../$(basename "$root")-worktrees/$TASK"
git worktree add "$WT" -b "$TASK" "<dev-branch>"     # dev branch: develop → dev → main, or per config
cmux new-workspace --name "LOOP-$TASK" --cwd "$WT" --focus false \
  --command "/loop-engine Run ticket <ID>: <one-line summary>. type=code qa=<on|off> poll=<on|off> dev-branch=<branch> worktree=$WT"
```
For each **ticked investigation ticket**, spawn at the repo root (no worktree/PR):
```bash
cmux new-workspace --name "ASK-$TASK" --cwd "$root" --focus false \
  --command "/loop-engine Investigate and answer ticket <ID>: <summary>. type=investigation"
```
- The `--command` text lands in the new workspace's auto-launched Claude as its first message (this user's cmux runs `claude` on new workspaces). ponytail: if a workspace does NOT auto-launch Claude, prefix the command with `claude ` so it starts one.
- Don't open more surfaces than tickets; `--focus false` so the user isn't yanked around. Stagger launches by a second or two if many, so worktree/branch creation doesn't race.

## Step 6 — Report
List what launched: each ticket → its cmux workspace name + worktree + branch, and the `qa`/`poll` settings. State they now run unattended to a PR (code) or a ticket comment (investigation), and that the user can watch each surface or check `task-env.sh list` for live app ports. Skipped tickets: name them so nothing's silently dropped.

## Rules
- **You investigate before you ask.** The triage must reflect the real codebase + ticket, not a guess from the title.
- **Nothing launches without the user's tick + confirm.** The checkbox list is the gate; respect exactly what they toggle.
- **Honor saved tracker config** (Linear/Jira team/project from the `ticket` skill) — don't re-ask. The user edits `.claude/tickets.local.json` to change it.
- **Skips are explicit.** Every pulled ticket lands in exactly one bucket and is shown; never quietly drop one.
- **Reuse the pieces.** Tickets via the tracker MCP (Linear/Jira) / the `ticket` skill; per-ticket execution via `loop-engine`; surfaces via cmux; any other connected MCP for enrichment. You only orchestrate.
