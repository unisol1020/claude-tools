# claude-loop

Hand Claude Code a task — a ticket URL, a ticket id, or a one-line description — and it runs the whole thing to a finished PR without you babysitting it: investigate, plan, build, rule-check against your `CLAUDE.md`, QA on a live app, open the PR, and watch for review comments until the PR is approved. On top of that sits an **investigator** that turns *"get 10 tickets from Linear and check them"* into a reviewed, parallel batch — it triages each ticket against your actual codebase, you tick the ones to run, and it fans out one autonomous loop per ticket. Every task gets its own git worktree and its own isolated Docker stack (own DB, Docker-assigned ports), so up to ten of these run side by side without stepping on each other.

## How it works

There are two entry points. The **investigator** is the morning conductor: it pulls tickets, sorts them, and lets you pick which ones to launch. Each pick becomes a **loop-engine** run — the per-task state machine that actually does the work.

### The investigator: pull, triage, fan out

```mermaid
flowchart TD
  A["You: get 10 tickets<br/>from Linear and check them"] --> B[Pull N tickets<br/>from the tracker]
  B --> C[Investigate each<br/>against THIS codebase]
  C --> D{Triage into<br/>three buckets}
  D --> E["RUN IN LOOP<br/>(code)"]
  D --> F["SKIP / DO SEPARATELY<br/>(with why)"]
  D --> G["INVESTIGATE ONLY<br/>(no code)"]
  E --> H[Checkbox list]
  F --> H
  G --> H
  H --> I[You tick which to start,<br/>then confirm]
  I --> J["Ask once: QA on/off?<br/>poll on/off?"]
  J --> K[Fan out: one git worktree +<br/>one cmux surface per ticket]
  K --> L[loop-engine runs<br/>each ticket unattended]
```

You say how many tickets to pull. The investigator reads each one, looks at your repo, and drops every ticket into exactly one of three buckets: **run in the loop** (well-scoped, Claude can build + QA + PR it), **skip / do separately** (too broad, needs a human, or risky to run unattended — with the reason), or **investigate only** (really a support/research question it can answer by posting findings on the ticket, no code). You get a scannable checklist, tick what you want, and confirm. It asks once whether to keep the tester and the PR-comment poll on, then spawns one loop per ticket — each in its own worktree, each in its own cmux surface. Nothing launches until you confirm.

### The loop-engine: one task, end to end

```mermaid
flowchart TD
  S[Task in: URL / id / description] --> P["PLAN ONCE — investigate +<br/>embed the ticket's Figma + screenshots"]
  P --> IMPL[Implement the plan]
  IMPL --> RC{Rule-check<br/>vs CLAUDE.md}
  RC -->|fails| IMPL
  RC -->|passes| QA{Manual QA<br/>on live isolated app}
  QA -->|bug| IMPL
  QA -->|clean| PR[Find/create ticket,<br/>open PR to dev branch]
  PR --> POLL[Poll PR every 5 min<br/>for review + CodeRabbit comments]
  POLL -->|new comment| IMPL
  POLL -->|approved| STOP[Tear down env, report, done]
```

The plan is built **once**, up front, and saved outside the repo at `$(task-env statedir)/<task-id>.plan.md`. It always embeds the ticket's design — Figma links and screenshots, rendered via a Figma MCP if one is connected — in a Design section that the implement and QA steps build and check against.

Then two nested loops. The **inner loop** is implement → rule-check against the project's `CLAUDE.md` (fix and re-check on fail) → manual QA on the live, isolated app (design QA compares the running UI to the plan's design refs). Any QA bug loops back to the fix and re-runs until QA is clean — reusing the plan, not re-planning. The **outer loop** finds or creates the ticket, opens a PR against the dev branch, then polls every 5 minutes (via Claude Code's built-in `/loop`) for reviewer and CodeRabbit comments, addresses each through the inner loop, and stops the moment the PR is approved.

Both the QA step and the poll are toggles, on by default. Drop either per run with `qa=off` / `poll=off`.

**Guardrails, because these run unattended and in parallel.** A runaway guard caps fix/comment rounds and the poll window, so a loop that isn't converging pauses and pings you instead of grinding tokens forever. Risk guardrails make high-risk changes — DB migrations, secrets/auth, infra, prod config, mass deletes, major dependency bumps, or anything your `CLAUDE.md` marks do-not-touch — escalate to you rather than ship on their own.

**Per-task isolation.** At the QA step the **devops** agent brings up a stack scoped to that one task — its own containers, volumes, network, and database — on host ports Docker picks (so ten tasks never collide). A ready stack is reused, not rebuilt. Any tester or dev can reach a task's app with `task-env ports <task-id>` and follow the run with `task-env progress <task-id>`, a journal the loop appends to after every step.

**Uses whatever MCP you've connected.** At each step the loop reaches for the connected, relevant MCP and falls back to CLI when there isn't one: **Linear or Jira** as the tracker, a **GitHub** MCP (or `gh`) for the PR and review threads, **Figma** for design context, **Sentry** for real error context on bugs, **Supabase/Postgres/MySQL** to inspect or seed the task's isolated DB, **Slack/Notion/Drive** for the thread or spec behind a ticket. None is required beyond a tracker — connect more and the loop just uses them.

## What you get

| Piece | Type | Role |
|-------|------|------|
| `skills/loop-engine/` | skill | the nested state machine — plan once, inner loop, outer loop, toggles, investigation mode |
| `skills/investigator/` | skill | pulls and triages tickets, fans out one loop per chosen ticket |
| `agents/devops.md` | agent | per-task isolated app+DB env; returns assigned ports to QA; tears down on finish |
| `bin/task-env.sh` (`task-env`) | CLI | the isolation engine — per-task Docker stack on auto-assigned ports + a manifest testers/devs read |

It **reuses** the rest of claude-tools instead of duplicating it — both live in this same repo: [`qa/`](https://github.com/unisol1020/claude-tools/blob/main/qa/README.md) (manual-qa + qa-run) for the QA step, [`tickets/`](https://github.com/unisol1020/claude-tools/blob/main/tickets/README.md) (the `ticket` skill) to find/create the ticket, and Claude Code's built-in `/loop` for polling.

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
> 4. **Make sure the pieces it reuses are installed too** — they ship in this same repo (the clone in step 2 already contains them): run `~/.claude-tools/qa/install.sh` ([qa README](https://github.com/unisol1020/claude-tools/blob/main/qa/README.md)) and `~/.claude-tools/tickets/install.sh` ([tickets README](https://github.com/unisol1020/claude-tools/blob/main/tickets/README.md)) if they aren't, and confirm a **tracker MCP (Linear or Jira)** is connected. Any other MCP (GitHub, Figma, Sentry, Supabase/Postgres, Slack, …) is optional — the loop uses whatever's there. (Claude Code's `/loop` is built in.)
> 5. **Verify:** `ls -la ~/.claude/skills/loop-engine ~/.claude/skills/investigator ~/.claude/agents/devops.md` are symlinks into `~/.claude-tools/loop`, and `command -v task-env` resolves.
> 6. **Report back to the user** — confirm it's installed, list any `✗` dependencies the installer printed with their `brew` commands, tell them to **restart Claude Code once**, then explain it in two lines:
>    > ✅ **Installed.** Two ways to use it: say *"get 10 tickets from Linear and check them"* (the investigator triages and, on your OK, fans out one autonomous loop per ticket), or *"take this task and run the loop: …"* (runs the loop engine on one task). Add `qa=off` / `poll=off` to drop the tester or the PR-comment poll. Inspect live task app ports with `task-env list`.
>
> Update later with `git -C ~/.claude-tools pull` (symlinks pick it up). Uninstall: see the bottom of this file.

### Manual install

```bash
git clone https://github.com/unisol1020/claude-tools.git ~/.claude-tools
~/.claude-tools/loop/install.sh
~/.claude-tools/qa/install.sh        # the QA step      → github.com/unisol1020/claude-tools/tree/main/qa
~/.claude-tools/tickets/install.sh   # the ticket step   → github.com/unisol1020/claude-tools/tree/main/tickets
```
Then restart Claude Code. (`qa` and `tickets` are part of the same `claude-tools` repo cloned above — these are the GitHub sources, not separate downloads.)

## Requirements

[Claude Code](https://claude.com/claude-code), git, and a connected **tracker** MCP (**Linear or Jira**). Then, for the parts that use them: **Docker** + **jq** for the per-task envs, **gh** for PRs, and **cmux** (macOS) for the investigator's fan-out surfaces. The [`qa`](https://github.com/unisol1020/claude-tools/blob/main/qa/README.md) and [`tickets`](https://github.com/unisol1020/claude-tools/blob/main/tickets/README.md) tools from this repo are reused by the loop. Any other MCP — GitHub, Figma, Sentry, Supabase/Postgres, Slack, Notion — is optional and used when it's there.

## Use it

- **Batch from Linear:** *"get 10 tickets from Linear and check them"* → review the checkbox triage → tick what to run → confirm → choose QA/poll → it runs unattended.
- **One task directly:** *"take this task and run the loop: add CSV export to the reports page; must match the Figma, keep the existing column order, and stay under the 5MB response cap."* Every constraint you list is carried into the plan.
- **From a ticket link:** *"run this ticket in the loop: https://linear.app/…/ENG-123"* (Linear or Jira URL). It fetches the issue, pulls its Figma/screenshots into the plan and the QA design reference, and runs.
- **Toggles per run:** *"…run the loop, qa=off"* · *"…poll=off"* · *"…qa=off poll=off"*.

## Per-task isolation & ports (for testers and devs)

Each task gets `COMPOSE_PROJECT_NAME=loop_<repo>_<task>` — its own containers, volumes, network, and DB — on host ports the Docker daemon picks, so nothing collides across 1–10 tasks. The assigned ports live in a manifest you can read directly:

```bash
task-env up    eng-123 ../myrepo-worktrees/eng-123   # bring up (or reuse) the task's stack
task-env ports eng-123                                # print its web/api/DB URLs
task-env list                                         # all live task stacks + ports + each one's latest progress line
task-env progress eng-123                             # the task's running progress journal (context for any agent)
task-env statedir                                     # where per-task plans/manifests/journals live (outside every repo)
task-env down  eng-123 ../myrepo-worktrees/eng-123    # tear down (containers + volumes)
```

Per-task state — the **plan** (`<task-id>.plan.md`), a **progress journal** (`<task-id>.progress.md`, a 1–3 line note the loop appends after every step so any agent has running context), the env manifest (`<task-id>.json`), and the poll state — all live in `task-env statedir` (`~/.cache/loop-engine` by default; set `LOOP_ENV_DIR` to relocate), keyed by task id and **outside every worktree**. So parallel tasks never share state and nothing leaks into a commit or PR. The manifest is also copied to `<worktree>/.claude/task-env.json` for convenience. No `docker-compose.yml` in the repo? The devops agent falls back to running the repo's dev command on a free port per task.

## Uninstall

```bash
rm ~/.claude/skills/loop-engine ~/.claude/skills/investigator ~/.claude/agents/devops.md ~/.local/bin/task-env
# tear down any leftover task stacks first:  task-env list  → task-env down <id> <worktree>
```
