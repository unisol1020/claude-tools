---
name: loop-engine
description: Autonomous task-execution loop — a loop-within-a-loop state machine. Hand it a task — a ticket URL, a ticket id, or a description — and it runs end to end without further input. It first builds a detailed up-front plan ONCE (always embedding the ticket's design — Figma links + screenshots), then executes. INNER LOOP — implement → rule-check against the project's CLAUDE.md (fix + re-check on fail) → manual QA; any QA bug loops back to the fix until QA passes clean, reusing the plan rather than re-planning. OUTER LOOP — find or create the ticket (Linear or Jira), open a PR to the dev branch, poll the PR every 5 min for reviewer/CodeRabbit comments, address each, and stop when the PR is approved. Manual QA and PR-comment polling are toggleable options, both ON by default. Each task runs in its own git worktree + isolated Docker stack (own DB) so parallel tasks never collide. Use when the user says "run the loop", "take this task and run the loop", "run this ticket in the loop: <url>", or when the investigator spawns a per-ticket run.
---

# loop-engine — autonomous nested task loop

You run ONE task to completion without asking for more input. You are usually spawned by the **investigator** into a dedicated cmux surface inside the task's worktree; you also run when a user hands you a task directly. Either way: investigate + build a detailed plan **once**, run the inner loop until QA is clean, then run the outer loop until the PR is approved.

## Inputs (parse from the invocation; don't ask unless run interactively with nothing given)
- **Task** — a **ticket URL** (e.g. `https://linear.app/<org>/issue/ENG-123/…` or `https://<site>.atlassian.net/browse/PROJ-123`), a ticket id, and/or a description, including **every constraint / lens** the user specified. **If given a URL** (e.g. "run this ticket in the loop: <url>"), extract the issue key from it and fetch the full issue from its tracker (Linear/Jira MCP) first — that's the task. Constraints are requirements, not suggestions — carry them into the plan.
- **Type** — `code` (default: build it, ship a PR) or `investigation` (a support/research question to answer, **no code** — see the bottom).
- **Options** (both ON by default): `qa` and `poll`. Honor whatever was requested for this run — `QA=off`, `poll=off`, "disable both", etc.
- **Dev branch** — the PR base. Detect (`develop` → `dev` → `main`) or use what config/CLAUDE.md says.

Set the cmux sidebar status as you move through phases so the run is legible from outside (`cmux set-status loop "<phase>"`, `cmux set-progress`, `cmux log`). Detect cmux first: `[ -S "${CMUX_SOCKET_PATH:-/tmp/cmux.sock}" ]`.

## Use any MCP you can see
Discover what's connected **this session** (`claude mcp list` + this session's deferred-tool list — names change, so check live), and load a tool's schema with **ToolSearch** before calling it. At every step, reach for whatever MCP is connected **and** relevant — never require a specific one, never invent a call, and fall back to the CLI/built-ins when it isn't there:
- **Tracker — Linear *or* Jira** (whichever the `ticket` skill detected for this repo): read the ticket, post comments, move status. Don't assume Linear; use the project's tracker.
- **GitHub** (a GitHub MCP, if connected): open/inspect the PR, read reviews + CodeRabbit threads, reply on comments — otherwise use `gh`.
- **Figma**: pull the frame / design context a ticket references — for the plan, and for design QA.
- **Sentry**: real exception + stack context when the task is a bug.
- **Supabase / Postgres / MySQL**: inspect or seed the task's **isolated** DB during QA (read-only by default; the devops manifest gives the per-task DB url).
- **Slack / Notion / Drive**: the original thread, spec, or PRD behind the ticket.

Rule: **installed AND relevant only** — one real signal beats a dump, and connected-but-irrelevant or not-connected → skip silently and use the fallback. This list is examples, not a fixed set: if the user has another useful MCP connected, use it where it helps.

## Keep a progress journal (so any agent has running context)
After **every step — whether it passed or failed** — append a 1–3 line note to the task's progress journal: what you just did, the resulting state, and the next action. On a failure, say what failed and what you're doing about it (fix / retry / escalate). This way you, any subagent you spawn (devops, manual-qa), and a human peeking in always know what's going on and where the run is:
```bash
task-env log <task-id> "<PHASE> — what you just did; resulting state; next action"
# e.g. task-env log eng-123 "PLAN — wrote detailed plan w/ Figma design refs; next: implement step 1 (checkout total)"
```
The journal lives at `$(task-env statedir)/<task-id>.progress.md` (per task, outside the repo — never committed). Read it back any time with `task-env progress <task-id>`; **when you spawn a subagent, give it the task id and tell it to run `task-env progress <task-id>` for context** (and to `task-env log` its own outcome). Log at least: investigation done, plan saved, each implement, each rule-check result, each QA verdict, ticket/PR opened, every comment addressed, and the final stop. Mirror the one-line headline to cmux too (`cmux set-status` / `cmux log`) for the live sidebar.

## Guardrails — don't let an unattended loop run away or do something risky
You're often one of up to 10 parallel, indefinitely-polling, unattended runs — so two backstops, both tracked in `<task-id>.state.json` and journaled:

**Runaway / cost guard.** You can't meter tokens from inside the run, so cap *iterations*, not dollars. Soft defaults (override per run, e.g. `max-fixes=8`): **QA-fix rounds ≤ 5**, **comment-fix rounds per poll ≤ 5**, **total poll window ≤ 24h**. When a cap is hit without converging (QA still failing, a comment you can't resolve, the window elapses), **stop and ping the user** with a one-line status + `task-env progress <task-id>` — don't keep grinding. Count each round in `state.json`; reset the QA counter only when a genuinely new approach starts.

**Risk guardrails (escalate, don't do unattended).** Before implementing — and before any comment-fix — check whether the change would touch a high-risk area: **DB migrations / destructive SQL, infra or IaC, auth / secrets / credentials, production config, mass deletes, or a major dependency bump** — plus anything the project's `CLAUDE.md` marks "do not touch". If so, **don't do it unattended**: pause, journal why, and ping the user for a decision (proceed only if the invocation explicitly authorized that area). The investigator already routes such tickets to "skip / do separately"; this is the loop's own backstop for when one slips through or a reviewer asks for it in a comment.

## Step 0 — Per-task isolation (worktree)
Each task must not share state with the others.
- **Task id** = the ticket key lowercased (`eng-123`), else a short slug of the description.
- **Worktree** — if you're not already in the task's worktree (the investigator may have created it and opened you there — check `git rev-parse --show-toplevel` and the branch), create it:
  ```bash
  git worktree add "../<repo>-worktrees/<task-id>" -b "<task-id>" "<dev-branch>"
  ```
  and work there. The isolated **Docker stack + DB** is created lazily at the QA step by the devops agent (check-or-create) — you don't bring it up until QA needs it, and `qa=off` runs may never need it.

---

## Plan once — investigate + design a detailed plan (first time only, before any code)

Do this **once**, up front, and do it well — a super-smart, detailed plan beats re-planning every iteration.

**1. Investigate deeply.** Understand the task in this codebase — CodeGraph if `.codegraph/` exists, else search/read. Read the ticket fully via the tracker MCP (Linear `get_issue` / the Jira equivalent). **Always check for and pull the ticket's design:** every attached **screenshot/image** and every **Figma link** on the ticket (and in the conversation). If a Figma MCP is connected, render the referenced frames (`get_screenshot` / `get_design_context`) so you hold the actual design, not just a URL. Also pull any other relevant context (Sentry error, Slack thread, Notion spec). Know the real files, the data flow, the acceptance criteria, **and the intended design** before planning — a UI/visual task investigated without its design is not ready to plan.

**2. Build a detailed plan (super smart).** Produce a thorough implementation plan that:
   - traces **every constraint / lens** from the task to exactly how you'll satisfy it,
   - lists the real files/areas you'll touch and the step-by-step approach,
   - **always embeds the design** — a **Design** section carrying the Figma links and the ticket's screenshots/images (rendered frames attached when a Figma MCP is connected). Whenever the ticket has any design, the plan MUST contain those links/images; never drop them. This Design section is the source of truth the implement + design-QA steps build and check against.
   Use the `make-plan` skill for a large task; plan inline for a small one. **Save the plan to the per-task state dir, keyed by task id — `"$(task-env statedir)/<task-id>.plan.md"`** (e.g. `~/.cache/loop-engine/eng-123.plan.md`). It lives **outside every worktree**, so 10 parallel tasks keep 10 separate plans and none of them ever lands in a commit or the PR. Never write the plan inside the repo/worktree.

The plan phase runs **once**. The inner loop below does **not** re-plan from scratch — it executes this plan and only updates the saved plan file when a QA bug or reviewer comment genuinely changes the approach.

---

## INNER LOOP — implement → check → QA (repeats until QA passes clean)

**3. Implement.** Build the plan. Match the surrounding code; follow the project's CLAUDE.md conventions as you write (don't save them all for the check). For any UI, the plan's **Design** section (Figma frames / screenshots) is your source of truth.

**4. Rule check (CLAUDE.md).** Read the project's `CLAUDE.md` (root + any nested ones in scope) and verify everything you built against it, rule by rule — conventions, comment policy, structure, anything it mandates. Also run the project's own gates if cheap and present (lint/typecheck/format/build). **If anything fails, fix it and re-check.** Don't leave this step until the work passes the project's own rules.

**5. Manual QA** *(skipped entirely if `qa=off`)*.
   a. **Bring up the env.** Spawn the **devops** agent (Agent tool): "Bring up the env for task `<task-id>` in worktree `<path>` and return the manifest." It returns the assigned **ports / URLs / DB url** (check-or-create — reuses a ready stack).
   b. **Test.** Invoke **qa-run** in *task mode* with that context (task id, worktree, the manifest's `primaryUrl`, the app's saved creds) — it runs the **manual-qa** agent against the live, isolated app. Functional by default; **design too whenever the plan has a Design section** — manual-qa compares the running UI against the plan's Figma frames / screenshots.
   c. **Verdict.** PASS / FAIL / PARTIAL with evidence.

**6. Loop back on a bug.** If QA returns a bug (FAIL/PARTIAL), **fix it**: make the change → **rule check (CLAUDE.md)** → QA again. Consult the saved plan (and its Design section); you don't rebuild it — update the saved plan file only if the fix changes the approach. Repeat until QA passes **clean**. (With `qa=off`, the inner loop ends after a clean rule check.)

When the inner loop passes, proceed to the outer loop (for a `code` task). 

---

## OUTER LOOP — PR lifecycle (repeats until approved)

**7. Ticket + PR.** Find the existing ticket for this task or create one in the project's tracker — **Linear or Jira**, whichever the **ticket** skill detected (reuse that skill, don't hand-roll ticket text). Commit on the task branch and open a **PR targeting the dev branch** (a GitHub MCP if connected, else `gh pr create --base <dev-branch>`). Link the PR to the ticket. Move the ticket to In Review.

**8. Poll for comments** *(skipped if `poll=off` — then go straight to step 11's "done for now")*. Wait for reviewer/CodeRabbit feedback by reusing **`/loop`** (Claude Code's recurring-interval skill) on a **5-minute** cadence. Each tick, read the PR's review decision + new comments/threads via the **GitHub MCP if connected**, else `gh`:
   ```bash
   gh pr view <pr> --json reviewDecision,reviews,comments
   gh pr view <pr> --comments        # inline + CodeRabbit threads
   ```
   Track which comment/review ids you've already handled (persist a small set in the per-task state dir — `"$(task-env statedir)/<task-id>.state.json"`, alongside the plan, **not** in the repo) so you only act on **new** ones. Between polls, idle — don't burn cycles.

**9. Address each new comment.** For every unaddressed reviewer/CodeRabbit comment, resolve it through the inner loop: implement the change → rule check (CLAUDE.md) → QA *(if `qa=on`)*. Consult the saved plan and update it only if the comment changes the approach — no full re-plan. Push the fix, then reply on the thread noting what you changed, and mark it handled.

**10. Keep polling.** Return to waiting for the next comment. Repeat 8–9.

**11. Stop on approval.** When the PR's `reviewDecision` is `APPROVED` (and CodeRabbit has no open actionable threads), **stop** — the task is complete. Tear the env down (devops `down`), report the final state (PR url, ticket, what shipped), `cmux notify` done. No more looping.
   - If `poll=off`: after opening the PR, report it's up for review and **stop without polling** — done for this run.

---

## Toggles (both ON by default; honor the requested combination)
- **`qa=off`** → skip step 5 entirely (no devops env, no manual-qa). Inner loop ends at a clean rule check.
- **`poll=off`** → skip steps 8–10. Open the PR and stop; don't watch it.
- **both off** → inner loop → ticket + PR → done. No QA, no polling.

## Investigation-only tasks (`type=investigation` — no code)
A support/research question that the investigator flagged as "answer without coding". Don't make a worktree, env, or PR. **Investigate** thoroughly (codebase + the ticket's context + any connected MCP that helps — Sentry for errors, the DB MCP for data questions, GitHub for history, Slack/Notion for the original thread), then **post the answer as a comment on the ticket** in its tracker (Linear or Jira; create the ticket only if asked), and report it. That's the whole loop for this type.

## Rules
- **End to end, no hand-holding.** Once started, run to the stop condition. Only stop early for a true blocker (e.g. QA `BLOCKED_AT_LOGIN` with no saved creds, or a missing prerequisite) — then say exactly what's needed.
- **Rule check is mandatory every iteration.** Every implement — initial or a fix — is followed by the CLAUDE.md check before QA. Never QA or push code that hasn't passed it.
- **Plan once, then execute.** The detailed plan is built one time, before coding, and saved per task to `"$(task-env statedir)/<task-id>.plan.md"` — outside every worktree, never in the repo (so it can't leak into a commit/PR, and 10 tasks never share one file). Loop iterations (QA fixes, reviewer comments) execute that plan and update it only when the approach genuinely changes — they never re-plan from scratch.
- **Journal every step.** After each phase, `task-env log <task-id> "…"` (1–3 lines: what, where, next). The per-task journal is the shared running context for every agent in the run — keep it current.
- **Guardrails over grind.** Respect the runaway caps and the risk denylist (see Guardrails). When a cap is hit or a change is high-risk, pause and ping the user — never loop forever or touch something risky unattended.
- **Design always travels with the plan.** If the ticket has any design — a Figma link or a screenshot/image — the plan's **Design** section must carry it, implementation builds to it, and QA checks against it. Never plan or build a UI task without its design in hand.
- **QA never fakes a pass.** A clean QA traces to something manual-qa actually observed on the live, isolated env.
- **Isolation is per task.** Your worktree + your Docker project only; never touch another task's branch, containers, or volumes.
- **Reuse, don't reinvent.** ticket → the `ticket` skill; QA → `qa-run`/`manual-qa`; env → the `devops` agent; polling → `/loop`. You orchestrate them.
