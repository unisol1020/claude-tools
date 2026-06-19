# claude-qa

Shareable QA toolset for **Claude Code** — a global `manual-qa` agent that drives a real browser to verify whether a feature *actually works* in any local web project, plus the skills it runs on.

One agent, **two modes**, picked from how you ask:

- **Functional** — *"does it work"*: thinks like a **senior QA first** — plans a charter across the **success path, error path, and the edge cases a real user will actually hit** (weird input, double-submit, back/refresh mid-flow, expired session, empty/overflowing data, slow/offline, …) — then click-through flows, forms, error states, mobile/offline via **Playwright MCP** (headless, fast, cross-platform).
- **Design** — *"does it look right / match Figma / pixel-perfect"*: screenshots the running UI and compares it to a **Figma frame or reference screenshot** at a **≥90% / 1:1** bar, reporting every difference. To capture the UI it uses the first available of: **cmux** (macOS, truest render) → Claude Desktop browser → Chrome-connected browser → **Playwright** headless screenshot → else it tells you to enable one.

On the first QA run in a project it asks — once — for local-dev login credentials and a read-only DB URL (via a connected DB MCP like Supabase, or `psql` if you have no MCP), remembers your choice per project (including "no, don't ask again"), and never nags you again.

> **💡 Recommended: run it inside `cmux` (macOS native terminal app) or the Claude Desktop app.** Both give a real browser / WebView, so the agent can open and screenshot the live UI at the truest fidelity — best for design / "does it look right" checks. A plain terminal works too: functional QA falls back to headless Playwright everywhere.

## What you get

| Piece | Type | Role |
|-------|------|------|
| `agents/manual-qa.md` | global agent | drives the browser like a human QA engineer; reports PASS/FAIL; never edits code |
| `skills/playwright-qa/` | skill | the headless-browser playbook (loop, capabilities, when-to-use vs cmux) |
| `skills/qa-run/` | skill | orchestrator: per-project credential + DB setup (ask once, remember), then runs `manual-qa` |

## Install — just send this README to Claude Code

You don't run anything. Paste this file (or its URL) into **Claude Code** and say *"install this"*. Claude does the rest.

> **🤖 Claude Code — if a user sent you this README, install the toolset now. Do not ask setup questions (credentials/URLs/DB are gathered per-project on the first QA run, not at install). Steps:**
>
> 1. **Preflight.** Confirm `git`, `node`/`npx`, and the `claude` CLI are on PATH. If any is missing, stop and tell the user to install it first.
> 2. **Clone (idempotent):**
>    ```bash
>    git clone https://github.com/unisol1020/claude-tools.git ~/.claude-tools 2>/dev/null \
>      || git -C ~/.claude-tools pull --ff-only
>    ```
> 3. **Run the installer:**
>    ```bash
>    bash ~/.claude-tools/qa/install.sh
>    ```
>    It symlinks the `manual-qa` agent + `playwright-qa` and `qa-run` skills into `~/.claude/`, and registers the **Playwright MCP** at user scope (`npx @playwright/mcp@latest --headless`).
> 4. **Verify:** `claude mcp get playwright` shows *Connected*; `ls -la ~/.claude/agents/manual-qa.md ~/.claude/skills/playwright-qa ~/.claude/skills/qa-run` are symlinks into `~/.claude-tools/qa`.
> 5. **Report back to the user** — confirm it's installed, then explain how it works in this simple step-by-step (paraphrase naturally, keep it short):
>
>    > ✅ **Installed.** Restart Claude Code once so the browser tools and the QA agent load.
>    >
>    > **How to use it — just ask, no commands:**
>    > 1. Start your app's dev server (so there's a URL to open).
>    > 2. Tell me what to check, in plain words:
>    >    - *Does it work?* → "check if login works", "verify checkout", "does the Save button actually save?"
>    >    - *Does it look right?* → "does /pricing match this Figma <link>", "is the header pixel-perfect vs this screenshot?"
>    > 3. **First time in a project** I'll ask you once (and remember per project): which app + its **URL** (localhost by default; a non-localhost URL is used only at your own risk), whether to use a **login** (or "no, never ask"), and how to verify the **DB** — via a connected MCP (e.g. Supabase), or `psql` with a read-only **DB URL** you provide (local/dev — prod only at your own risk).
>    > 4. I then drive a **real browser** and report **PASS / FAIL** with exactly what I saw. For *works* checks I follow the flow, click, and watch for errors. For *looks-right* checks I screenshot the page and compare it to your Figma/screenshot at a **90%+ / 1:1** bar and list every difference.
>    > 5. For a design check, **give me a Figma link or a screenshot** of the target — if you don't, I'll ask for one.
>    > 6. Your logins live only in a local, git-ignored file (local-dev only) — never committed, never shown back to you.
>    > 7. 💡 For the best experience run me inside **cmux** (macOS) or the **Claude Desktop** app — both give a real browser/WebView so I see and screenshot the live UI at truest fidelity (great for design checks). A plain terminal is fine too; functional checks fall back to headless Playwright.
>    >
>    > That's it. Try: *"QA the login flow"* or *"does the dashboard match this Figma: <link>"*.
>
> Update later with `git -C ~/.claude-tools pull` (symlinks pick it up). Uninstall: see the bottom of this file.

Requirements: [Claude Code](https://claude.com/claude-code), Node.js (for `npx`), git. **Recommended runtime:** `cmux` (macOS) or the Claude Desktop app — a real browser/WebView for truest render. Both optional: functional QA needs only the Playwright MCP and runs in any terminal.

### Manual install (if you'd rather)

```bash
git clone https://github.com/unisol1020/claude-tools.git ~/.claude-tools
~/.claude-tools/qa/install.sh
```
Then restart Claude Code.

## Use it (in any project)

1. Start the project's dev server (so there's a URL).
2. Ask Claude Code, in plain words:
   - *"QA the login flow"* · *"verify checkout works"* · *"check if the save button on /settings actually fires a request"* · *"test the dashboard on a mobile viewport"*
3. **First run in that project**, the `qa-run` skill detects whether it's a single app or a **monorepo** (and which apps exist), then asks:
   - **Which app** is in scope (only if multiple and ambiguous).
   - **What URL** to use for that app — pre-filled from the detected dev port. In a monorepo it remembers a URL **per app** (e.g. web-a :3000, web-b :3001, web-c :3002). localhost is the default; you *can* point it at a non-localhost URL (staging/preview/prod), but it'll warn you once that QA exercises a live environment **at your own risk** before using it.
   - **Login credentials** for that app — *Provide* (local-dev only) or *Decline (never ask again)*. Remembered per app.
   - **DB verification?** If a DB MCP (Supabase, Postgres, …) is connected, it offers to read via that. If none is connected, it asks whether to **install a DB MCP**, use **`psql` with a DB URL you provide**, or *Decline (never ask again)*. The URL should be a **local or dev** database — a prod URL is only used after you accept the risk, and queries stay read-only.
4. It then runs `manual-qa`, which drives a headless browser and reports **PASS / FAIL / PARTIAL** with evidence.

If a check needs login but you declined credentials, manual-qa stops at the wall and **pings you** (`BLOCKED_AT_LOGIN`) instead of guessing or faking a pass.

## Per-project memory

Your choices are stored in `<project>/.claude/qa.local.json` (see `templates/qa.local.json.example`). URLs + credentials are **per app** (monorepo-friendly); the DB is project-level:

```jsonc
{
  "apps": [
    { "name": "web-a", "url": "http://localhost:3000",
      "credentials": { "status": "set", "loginUrl": "...", "username": "...", "password": "..." } },
    { "name": "web-b", "url": "http://localhost:3001", "credentials": { "status": "declined" } }
  ],
  "db": { "status": "set|declined|no-mcp", "access": "mcp|psql", "tool": "mcp__<server>__<readonly_sql_tool> | psql", "url": "...", "env": "local|dev|prod" }
}
```

`status` is the memory: `set` use it · `declined` never ask again · `no-mcp` no DB MCP present. Change your mind by editing (or deleting) the file.

### ⚠️ Credentials & privacy

- `qa.local.json` holds **local-dev credentials** → it is **gitignored** and must **never** be committed. `qa-run` adds it to your project's `.gitignore` before writing anything.
- **Local-dev by default; non-localhost is your call.** Prefer local-dev URLs and credentials. You *can* aim QA at a staging/preview/prod URL, but it's allowed only after a one-time warning that QA drives a live, possibly shared environment (forms submitted, writes triggered, real services hit) — **all risk is on you**. The agent never prints passwords in reports.
- This repo itself contains **no secrets** — only the tooling and a placeholder template.

## Tool split

- **Playwright MCP** — functional QA: flows, forms, error states (network mocking), mobile/offline/geo, CI. The default.
- **cmux** (macOS, optional) — design/visual confirmation in a real desktop WebView. Used only for "does it look right".
- **Maestro** — native mobile-app flows (not part of this toolset; use it directly for RN/native).

## Override per project

A project can ship its own `.claude/agents/manual-qa.md` to specialize the agent (project URLs, a DB cross-check tool, extra conventions). A project-scoped agent of the same name takes precedence over this global one — intended behavior.

## Uninstall

```bash
rm ~/.claude/agents/manual-qa.md ~/.claude/skills/playwright-qa ~/.claude/skills/qa-run
claude mcp remove playwright -s user
rm -rf ~/.claude-tools
```
