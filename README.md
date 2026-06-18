# claude-qa

Shareable QA toolset for **Claude Code** — a global `manual-qa` agent that drives a real browser to verify whether a feature *actually works* in any local web project, plus the skills it runs on.

One agent, **two modes**, picked from how you ask:

- **Functional** — *"does it work"*: click-through flows, forms, error states, mobile/offline — via **Playwright MCP** (headless, fast, cross-platform).
- **Design** — *"does it look right / match Figma / pixel-perfect"*: screenshots the running UI and compares it to a **Figma frame or reference screenshot** at a **≥90% / 1:1** bar, reporting every difference. To capture the UI it uses the first available of: **cmux** (macOS, truest render) → Claude Desktop browser → Chrome-connected browser → **Playwright** headless screenshot → else it tells you to enable one.

On the first QA run in a project it asks — once — for local-dev login credentials and (if a DB MCP is connected) a read-only DB URL, remembers your choice per project (including "no, don't ask again"), and never nags you again.

## What you get

| Piece | Type | Role |
|-------|------|------|
| `agents/manual-qa.md` | global agent | drives the browser like a human QA engineer; reports PASS/FAIL; never edits code |
| `skills/playwright-qa/` | skill | the headless-browser playbook (loop, capabilities, when-to-use vs cmux) |
| `skills/qa-run/` | skill | orchestrator: per-project credential + DB setup (ask once, remember), then runs `manual-qa` |

## Install

Requires [Claude Code](https://claude.com/claude-code) and Node.js (for `npx`).

```bash
git clone git@github.com:unisol1020/claude-qa.git
cd claude-qa
./install.sh        # symlinks agent+skills into ~/.claude, registers the Playwright MCP (user scope)
```

Then **restart Claude Code** (MCP tools only surface on restart). Update later with `git pull` — symlinks pick it up.

## Use it (in any project)

1. Start the project's dev server (so there's a URL).
2. Ask Claude Code, in plain words:
   - *"QA the login flow"* · *"verify checkout works"* · *"check if the save button on /settings actually fires a request"* · *"test the dashboard on a mobile viewport"*
3. **First run in that project**, the `qa-run` skill detects whether it's a single app or a **monorepo** (and which apps exist), then asks:
   - **Which app** is in scope (only if multiple and ambiguous).
   - **What URL** to use for that app — pre-filled from the detected dev port. In a monorepo it remembers a URL **per app** (e.g. web-a :3000, web-b :3001, web-c :3002).
   - **Login credentials** for that app — *Provide* (local-dev only) or *Decline (never ask again)*. Remembered per app.
   - **DB verification?** Only if a DB MCP is connected: *Provide* a read-only DB URL or *Decline (never ask again)*.
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
  "db": { "status": "set|declined|no-mcp", "tool": "mcp__<server>__<readonly_sql_tool>", "url": "..." }
}
```

`status` is the memory: `set` use it · `declined` never ask again · `no-mcp` no DB MCP present. Change your mind by editing (or deleting) the file.

### ⚠️ Credentials & privacy

- `qa.local.json` holds **local-dev credentials** → it is **gitignored** and must **never** be committed. `qa-run` adds it to your project's `.gitignore` before writing anything.
- **Local-dev only.** Never enter staging/production credentials. The agent never types creds into a non-localhost URL and never prints passwords in reports.
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
```
