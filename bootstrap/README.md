# bootstrap

One command that makes a repo — and a teammate's fresh machine — **fully ready** for this Claude Code setup. No more "which extensions do I need, and how do I configure them?" A teammate clones a repo, runs **`/bootstrap`**, and everything gets installed, wired up, and indexed.

## What `/bootstrap` does

Installs **only what's missing** (idempotent, safe to re-run), then sets the project up:

| Extension | What it installs | How |
|-----------|------------------|-----|
| **ripgrep** | the `rg` binary | `brew install ripgrep` |
| **CodeGraph** | the `@colbymchenry/codegraph` CLI **+ its MCP server** in Claude Code, then a built index of the repo | `npm i -g @colbymchenry/codegraph` → `codegraph install -y` → `codegraph init` |
| **graphify** | the `graphifyy` PyPI package (provides the `graphify` CLI, Python 3.10+) **+ the `/graphify` skill** | `uv tool install graphifyy` → `graphify install` |
| **ponytail** | the ponytail Claude Code plugin (lazy-senior-dev mode — YAGNI, stdlib-first, fewest lines) | writes the marketplace + enable into `~/.claude/settings.json` |

Then it builds the **CodeGraph index** (`codegraph init`), offers to build the **graphify knowledge graph** (`/graphify`), augments **CLAUDE.md**, and records the repo in `~/.claude/.bootstrapped-projects` so the session-start nudge stops.

It also installs a **session-start hook** that nudges anyone to run `/bootstrap` in a not-yet-set-up repo, plus a **CodeGraph auto-sync** hook that keeps the index fresh.

## Install — send this README to Claude Code

> **🤖 Claude Code — if a user sent you this README, install it now. Steps:**
>
> 1. **Preflight.** Confirm `git`, `jq`, and the `claude` CLI are on PATH.
> 2. **Clone (idempotent):**
>    ```bash
>    git clone https://github.com/unisol1020/claude-tools.git ~/.claude-tools 2>/dev/null \
>      || git -C ~/.claude-tools pull --ff-only
>    ```
> 3. **Run the installer** (symlinks the `/bootstrap` skill + the nudge hook, wires the SessionStart hooks into `settings.json` — backs it up first):
>    ```bash
>    bash ~/.claude-tools/bootstrap/install.sh
>    ```
>    Add `--with-deps` to also install the extensions (ripgrep / CodeGraph / graphify / ponytail) right now. **Ask the user first** — it runs brew / npm / pip.
> 4. **Verify:** `ls -la ~/.claude/skills/bootstrap` is a symlink into `~/.claude-tools/bootstrap`.
> 5. **Report back:** tell the user to **restart Claude Code once**, then open any repo and run **`/bootstrap`** — it installs the required extensions if missing, builds the CodeGraph index, offers `/graphify`, and records the repo. The ponytail plugin + CodeGraph MCP surface after the restart.
>
> Update later with `git -C ~/.claude-tools pull` (the symlink picks it up).

Requirements: macOS/Linux, [Claude Code](https://claude.com/claude-code), `git`, `jq`, and — for the extensions — `node`/`npm` (or volta), `python3`, and Homebrew (for ripgrep). The installer installs the gaps.

### Manual install

```bash
git clone https://github.com/unisol1020/claude-tools.git ~/.claude-tools
~/.claude-tools/bootstrap/install.sh          # add --with-deps to also install the toolchain now
```
Then restart Claude Code.

## For teammates — the short version

1. Install this once (above).
2. Open any repo → Claude nudges you that it isn't bootstrapped → run **`/bootstrap`**.
3. That's it. Everything the projects here expect is installed, configured, and the repo is indexed.

Prefer to set the toolchain up from a terminal without opening a repo? Run the bundled setup script directly — it installs only what's missing:

```bash
bash ~/.claude/skills/bootstrap/setup-env.sh
```

## What's in the box

| File | Role |
|------|------|
| `skills/bootstrap/SKILL.md` | the `/bootstrap` flow Claude runs per repo |
| `skills/bootstrap/setup-env.sh` | idempotent installer for the four extensions (also runnable standalone) |
| `hooks/bootstrap-check.sh` | SessionStart nudge — fires in any not-yet-bootstrapped repo |
| `install.sh` | symlinks the skill + hook, wires the SessionStart hooks into `settings.json` |

## Privacy

`~/.claude/.bootstrapped-projects` lists the **real repo paths** you've set up. It lives under `~/.claude` and is **never** committed to this (or any) repo — only the generic tooling ships here.

## Uninstall

```bash
rm ~/.claude/skills/bootstrap ~/.claude/hooks/bootstrap-check.sh
# then remove the SessionStart entries for bootstrap-check.sh / codegraph sync from ~/.claude/settings.json
```
