# claude-loop

An autonomous **loop engine** for Claude Code — hand it a task and it runs a loop-within-a-loop to completion, plus an **investigator** that turns *"get 10 tickets from Linear and check them"* into a reviewed, parallel batch. Each task runs in its own git worktree + isolated Docker stack (its own DB, its own ports), so 1–10 tasks run side by side without clobbering each other.

## How it works

**Investigator (morning conductor).** *"Get N tickets from Linear and check them"* → it pulls the tickets, investigates each against **your** codebase, and hands back a checkbox triage:

```
RUN IN LOOP (code)        ← Claude Code can build + QA + PR these autonomously
SKIP / DO SEPARATELY      ← too broad / needs a human / risky unattended (with why)
INVESTIGATE ONLY (no code)← support/research questions it answers on the ticket
```

You tick which to start. On your confirm it asks once — *keep the tester (QA) and the PR-comment poll on, or disable either?* — then fans out fully autonomously: one cmux surface per ticket, each running the loop engine.

**Loop engine (per task).** *"Take this task and run the loop"* — or just paste a link: *"run this ticket in the loop: https://linear.app/…/ENG-123"* (it resolves the URL to the issue).

- **Plan once, up front** — investigate deeply, **always pulling the ticket's design** (Figma links + screenshots, rendered via a Figma MCP if connected), and write a detailed plan that honors every constraint you gave and **embeds that design** in a Design section. Saved **per task outside the repo** (`$(task-env statedir)/<task-id>.plan.md`), so 10 parallel tasks keep 10 separate plans and none leaks into a commit/PR; the loop executes it and only re-plans if an approach genuinely changes.
- **Inner loop** — implement → **rule-check against the project's `CLAUDE.md`** (fix + re-check on fail) → **manual QA** on the live isolated app (design QA compares the running UI to the plan's design refs). Any QA bug loops back to the fix until QA passes clean.
- **Outer loop** — find or create the ticket → open a **PR to the dev branch** → poll every **5 min** for reviewer / CodeRabbit comments (reuses Claude Code's `/loop`) → address each → **stop when the PR is approved**.

**Two toggles, both ON by default:** the **manual QA** step and the **PR-comment poll**. Disable either or both per run (`qa=off`, `poll=off`).

**Per-task isolation + DevOps agent.** At the QA step the **devops** agent brings up a stack scoped to that one task — its own containers, volumes, network and **database** — on host ports Docker assigns, and returns the URLs/DB to QA. A ready stack is reused, not rebuilt. Any tester/dev can reach a task's app: `task-env ports <task-id>`.

**Uses any MCP you've connected.** At every step the loop reaches for whatever MCP is connected *and* relevant — and falls back to CLI/built-ins when one isn't: **Linear *or* Jira** as the tracker, a **GitHub** MCP (or `gh`) for the PR + review/CodeRabbit comments, **Figma** for design context in planning and design QA, **Sentry** for real error context on bugs, **Supabase/Postgres/MySQL** to verify or seed the task's isolated DB, **Slack/Notion/Drive** for the thread or spec behind a ticket. Nothing is required — connect more useful MCPs and the loop just uses them; connect none beyond a tracker and it still runs on `gh` + Docker.

## What you get

| Piece | Type | Role |
|-------|------|------|
| `skills/loop-engine/` | skill | the nested state machine (inner + outer loop, toggles, investigation mode) |
| `skills/investigator/` | skill | pulls + triages Linear tickets, fans out one loop per chosen ticket |
| `agents/devops.md` | agent | per-task isolated app+DB env; returns assigned ports to QA; tears down on finish |
| `bin/task-env.sh` (`task-env`) | CLI | the isolation engine — per-task Docker stack on auto-assigned ports + a manifest testers/devs read |

It **reuses** the rest of claude-tools rather than duplicating it: `qa/` (manual-qa + qa-run) for the QA step, `tickets/` (the `ticket` skill) to find/create the Linear ticket, and Claude Code's `/loop` for polling.

## Install — just send this README to Claude Code

You don't run anything. Paste this file (or its URL) into **Claude Code** and say *"install this"*.

> **🤖 Claude Code — if a user sent you this README, install claude-loop now. Steps:**
>
> 1. **Preflight.** Confirm `git` and the `claude` CLI are on PATH. Note (don't block on) `docker`, `jq`, `gh`, and `cmux` — the installer reports which are missing.
> 2. **Clone (idempotent):**
>    ```bash
>    git clone https://github.com/unisol1020/claude-tools.git ~/.claude-tools 2>/dev/null \
>      || git -C ~/.claude-tools pull --ff-only
>    ```
> 3. **Run the installer:**
>    ```bash
>    bash ~/.claude-tools/loop/install.sh
>    ```
>    It symlinks the `loop-engine` + `investigator` skills and the `devops` agent into `~/.claude/`, and the `task-env` helper into `~/.local/bin`.
> 4. **Make sure the pieces it reuses are installed too** — run `~/.claude-tools/qa/install.sh` and `~/.claude-tools/tickets/install.sh` if they aren't, and confirm a **tracker MCP (Linear or Jira)** is connected. Any other MCP (GitHub, Figma, Sentry, Supabase/Postgres, Slack, …) is optional — the loop uses whatever's there. (Claude Code's `/loop` is built in.)
> 5. **Verify:** `ls -la ~/.claude/skills/loop-engine ~/.claude/skills/investigator ~/.claude/agents/devops.md` are symlinks into `~/.claude-tools/loop`, and `command -v task-env` resolves.
> 6. **Report back to the user** — confirm it's installed, list any `✗` dependencies the installer printed with their `brew` commands, tell them to **restart Claude Code once**, then explain it in two lines:
>    > ✅ **Installed.** Two ways to use it: say *"get 10 tickets from Linear and check them"* (the investigator triages and, on your OK, fans out one autonomous loop per ticket), or *"take this task and run the loop: …"* (runs the loop engine on one task). Add `qa=off` / `poll=off` to drop the tester or the PR-comment poll. Inspect live task app ports with `task-env list`.
>
> Update later with `git -C ~/.claude-tools pull` (symlinks pick it up). Uninstall: see the bottom of this file.

Requirements: [Claude Code](https://claude.com/claude-code), git, **Docker** + **jq** (per-task envs), **gh** (PRs), **cmux** (macOS, the fan-out surface), and a connected **tracker** MCP (**Linear or Jira**). The `qa` and `tickets` tools from this repo are reused by the loop. Any other MCP — GitHub, Figma, Sentry, Supabase/Postgres, Slack, Notion — is optional and used opportunistically.

### Manual install

```bash
git clone https://github.com/unisol1020/claude-tools.git ~/.claude-tools
~/.claude-tools/loop/install.sh
~/.claude-tools/qa/install.sh        # the QA step
~/.claude-tools/tickets/install.sh   # the ticket step
```
Then restart Claude Code.

## Use it

- **Batch from Linear:** *"get 10 tickets from Linear and check them"* → review the checkbox triage → tick what to run → confirm → choose QA/poll → it runs unattended.
- **One task directly:** *"take this task and run the loop: add CSV export to the reports page; must match the Figma, keep the existing column order, and stay under the 5MB response cap."* Every constraint you list is carried into the plan.
- **From a ticket link:** *"run this ticket in the loop: https://linear.app/…/ENG-123"* (Linear or Jira URL). It fetches the issue, pulls its Figma/screenshots into the plan + the QA design reference, and runs.
- **Toggles per run:** *"…run the loop, qa=off"* · *"…poll=off"* · *"…qa=off poll=off"*.

## Per-task isolation & ports (DX for testers and devs)

Each task gets `COMPOSE_PROJECT_NAME=loop_<repo>_<task>` — its own containers/volumes/network/DB — with host ports the Docker daemon picks (no collisions across 1–10 tasks). The assigned ports live in a manifest a human can read directly:

```bash
task-env up    eng-123 ../myrepo-worktrees/eng-123   # bring up (or reuse) the task's stack
task-env ports eng-123                                # print its web/api/DB URLs
task-env list                                         # all live task stacks + ports
task-env statedir                                     # where per-task plans/manifests live (outside every repo)
task-env down  eng-123 ../myrepo-worktrees/eng-123    # tear down (containers + volumes)
```

Per-task state — the **plan** (`<task-id>.plan.md`), the env manifest (`<task-id>.json`) and the poll state — all live in `task-env statedir` (`~/.cache/loop-engine` by default, set `LOOP_ENV_DIR` to relocate), **keyed by task id and outside every worktree**, so parallel tasks never share state and nothing leaks into a commit or PR. The manifest is also copied to `<worktree>/.claude/task-env.json` for convenience. No `docker-compose.yml` in the repo? The devops agent falls back to running the repo's dev command on a free port per task.

## Uninstall

```bash
rm ~/.claude/skills/loop-engine ~/.claude/skills/investigator ~/.claude/agents/devops.md ~/.local/bin/task-env
# tear down any leftover task stacks first:  task-env list  → task-env down <id> <worktree>
```
