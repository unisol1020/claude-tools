# cmux setup — my terminal + editor + Claude Code environment, 1:1

My full [cmux](https://cmux.com) workspace, captured so it can be reinstalled or shared exactly: a **glass terminal** (Ghostty, Catppuccin, transparent + blurred), a **flicker-free `fresh` editor** that file-opens route into, a **colorful Claude Code statusline**, and the cmux behaviors that tie them together. Send this README to Claude Code and say *"install this"* — it lays everything down (backing up whatever you already have) and tells you which dependencies to add.

## What it looks like

- **Terminal:** Ghostty rendering inside cmux — `Catppuccin Mocha` (dark) / `Latte` (light), auto-switching with macOS appearance, **92% opacity + 20px background blur** (the modern glass look), `JetBrainsMono Nerd Font` 14, roomy padding, a bar cursor that doesn't blink.
- **Statusline** (bottom of Claude Code) — colored segments split by gray `|`:
  `dir | ⎇ branch | ⇡ahead ⇣behind | ±files +adds -dels | context% | model 1M | ⬡ codegraph | [CAVEMAN]`
  Context % is green→amber→red as it fills; the `1M` badge marks a 1M-context model; `⬡` shows the CodeGraph index state; `[CAVEMAN]` is the caveman plugin's token badge.
- **Sidebar:** matches the terminal background, shows live log + progress.
- **Files** open in the `fresh` TUI editor in one persistent pane per workspace (no flicker, no new tabs); images/PDFs open in cmux's preview split.
- **New workspace** boots straight into `claude`.

## What's in the box

| File | Installs to | Role |
|------|-------------|------|
| `config/cmux.json` | `~/.config/cmux/cmux.json` | cmux app behavior (editor routing, sidebar, browser link handling, minimal mode) |
| `config/ghostty-config` | `~/.config/ghostty/config` | terminal rendering — **colors, theme, opacity, blur, font, cursor** |
| `config/open-in-micro.sh` | `~/.config/cmux/open-in-micro.sh` | `preferredEditor` wrapper — routes file-opens into a persistent `fresh` session |
| `config/fresh/catppuccin-mocha.json` + `config/fresh/config.snippet.json` | `~/.config/fresh/themes/` + merged into `~/.config/fresh/config.json` | `fresh` editor theme — **Catppuccin Mocha + terminal background**, so the editor matches the glass terminal |
| `config/statusline.sh` | `~/.claude/statusline.sh` | the Claude Code statusline (segments + colors) |
| `config/claude-settings.snippet.json` | merged into `~/.claude/settings.json` | statusLine / theme / tui / effort / model |
| `bin/db-tui.sh` | `~/.local/bin/db-tui` | open a terminal SQL client in a right-side cmux split |

## Install — send this README to Claude Code

> **🤖 Claude Code — if a user sent you this README, install it now. macOS only. Steps:**
>
> 1. **Preflight.** Confirm `git` and the `cmux` CLI are present (`brew install --cask cmux` if not). `jq` is needed for the statusline + settings merge.
> 2. **Clone (idempotent):**
>    ```bash
>    git clone https://github.com/unisol1020/claude-tools.git ~/.claude-tools 2>/dev/null \
>      || git -C ~/.claude-tools pull --ff-only
>    ```
> 3. **Run the installer** (it backs up every file it touches and MERGES Claude settings — never overwrites):
>    ```bash
>    bash ~/.claude-tools/cmux/install.sh
>    ```
> 4. **Offer the optional flags — ASK the user first, don't assume:**
>    - `--with-deps` → brew-installs `fresh-editor`, the JetBrains Mono Nerd Font, and `jq`. Ask before running brew.
>    - `--with-db` → brew-installs `harlequin` (the recommended terminal SQL client).
>    - `--bypass` → **SECURITY: also turns on `bypassPermissions`, which auto-approves *every* tool call with no prompt.** Only add this if the user explicitly asks for it; explain the risk first. The screenshot's "bypass permissions on" comes from this — it is OFF by default.
> 5. **Report back:** confirm what was written, list any `✗` dependencies the installer printed with their `brew` commands, and tell the user to **restart Claude Code once**. Mention the `[CAVEMAN]` badge needs the caveman plugin installed separately (step in the README).
>
> Update later with `git -C ~/.claude-tools pull` then re-run `install.sh`. Uninstall: restore the `.bak-*` files (see bottom).

### Requirements

- **macOS 14+** and **[cmux](https://cmux.com)** (`brew install --cask cmux`). cmux bundles Ghostty, so the `~/.config/ghostty/config` is read by cmux directly.
- **`fresh-editor`** — the `fresh` TUI editor the open-wrapper drives (`brew install fresh-editor`).
- **`jq`** (statusline + settings merge), **JetBrains Mono Nerd Font** (`brew install --cask font-jetbrains-mono-nerd-font`).
- Optional: **`harlequin`** for the DB TUI.

---

## Configure each part 1:1

### 1. Terminal colors / theme / glass — `~/.config/ghostty/config`

This is where **all visual terminal config** lives (cmux reads Ghostty's config; it is *not* in `cmux.json`).

```ini
theme = light:Catppuccin Latte,dark:Catppuccin Mocha   # auto light/dark; or a single theme name
background-opacity = 0.92      # 1.0 = solid, lower = more see-through
background-blur = 20           # macOS blur radius behind the transparency
unfocused-split-opacity = 0.85 # dim panes you're not focused on
font-family = "JetBrainsMono Nerd Font"
font-size = 14
font-thicken = true            # slightly bolder glyphs
window-padding-x = 14
window-padding-y = 12
window-padding-balance = true  # even padding on all sides
window-padding-color = background
cursor-style = bar             # bar | block | underline
cursor-style-blink = false
mouse-hide-while-typing = true
```

- **Change the theme:** `ghostty +list-themes` shows every built-in (Catppuccin, Dracula, Nord, Tokyo Night, Gruvbox, …). Set `theme = <name>` or the `light:…,dark:…` pair.
- **More/less glass:** drop `background-opacity` toward `0.80` for more transparency; set `background-blur = 0` to kill the blur.
- **Apply:** `cmux reload-config` (or **⌘⇧,**) — no app restart.

### 2. cmux behavior — `~/.config/cmux/cmux.json`

What this config changes from cmux defaults:

| Key | Value | Effect |
|-----|-------|--------|
| `app.preferredEditor` | the open wrapper | files open in `fresh` (see §3) instead of the default `zed` |
| `app.openSupportedFilesInCmux` | `false` | hand text/code to the wrapper rather than cmux's built-in editor |
| `app.openMarkdownInCmuxViewer` | `true` | `.md` opens in cmux's live markdown renderer |
| `app.minimalMode` | `true` | stripped-down chrome |
| `app.warnBeforeClosingTab` | `false` | no "are you sure" on close |
| `sidebar.showLog` / `showProgress` | `true` | live agent log + progress in the sidebar |
| `sidebarAppearance.matchTerminalBackground` | `true` | sidebar tint follows the terminal background (the glass look extends to the sidebar) |
| `terminal.showScrollBar` | `false` | no scrollbar |
| `fileExplorer.doubleClickAction` | `preferredEditor` | double-click a file → open in `fresh` |
| `shortcuts.bindings.switchRightSidebarToDock` | `cmd+shift+g` | custom keybind |
| `browser.*` | all `true` | terminal links, `localhost` ports, and PR links open in cmux's built-in browser |
| `newWorkspaceCommand` | `claude` | every new workspace launches Claude Code |

Edit with `cmux settings cmux-json`; the schema is referenced at the top of the file for autocomplete. Reload with `cmux reload-config`. **Back up first** — the installer keeps timestamped `.bak` copies, and so should manual edits.

### 3. The `fresh` editor + open-routing wrapper — `~/.config/cmux/open-in-micro.sh`

cmux calls this wrapper whenever you open a readable file (Cmd-click a terminal path, double-click in the file tree, click a Claude Code file mention). It:

- **images / PDF / audio / video** → cmux's built-in preview, split to the right.
- **text / code** → the [`fresh`](https://sinelaw.github.io/fresh/) TUI editor ([source](https://github.com/sinelaw/fresh)), in **one persistent session + pane per workspace**. The first open boots `fresh -a ws-<id>`; every later open routes the file into that already-running editor (`fresh --cmd session open-file`) — **no new tab, no shell boot, no flicker.** The pane UUID is remembered in `~/.config/cmux/fresh-pane-<ws>.id`; if it died, the wrapper respawns it. `fresh` launches at the **git repo root** so the workspace context stays put across a monorepo.

  Opens are **serialized per workspace** with an atomic `mkdir` lock (`~/.config/cmux/open-lock-<ws>.d`): two files opened at once (Claude mentioning several, a fast double-click) no longer each spawn their own surface — the second waits and routes into the session the first created.

**Theme:** the editor is set to **Catppuccin Mocha** with `editor.use_terminal_bg` on, so its background is the terminal's (the glass shows through) and its colors match cmux's dark theme. The installer ships the theme file and **deep-merges** just `theme` + `use_terminal_bg` into `~/.config/fresh/config.json` — your LSP, formatters, and other `fresh` settings are left untouched.

Install the editor: `brew install fresh-editor`. To use a different editor, point `app.preferredEditor` at it directly (e.g. `"zed"`, `"nvim"`) or edit `EDITOR_BIN` in the wrapper.

### 4. The statusline — `~/.claude/statusline.sh`

A bash script Claude Code runs to render the bottom bar (wired up via `statusLine` in settings). Segments, in order: **dir**, **⎇ branch**, **⇡ahead ⇣behind** vs upstream, **±files +adds -dels** (or **✓ clean**), **context %** (parsed from the live transcript; green <50%, amber 50–80%, red ≥80%), **model** (+ yellow `1M` badge for 1M-context models), **⬡ CodeGraph index** state (`✓` ok / `⚠` stale / `reindex` / `—` none), and the trailing **caveman** token badge.

- **Recolor:** the `C_*` variables near the top are ANSI-256 codes (`\033[38;5;<n>m`). Change a number, save — it's live on the next render.
- **Add/remove a segment:** each pushes onto the `segs` array; delete a block to drop it. The CodeGraph and caveman blocks no-op cleanly when those tools aren't installed.
- The **caveman badge** path is globbed, so it survives plugin updates. To get the `[CAVEMAN]` badge at all you must install the caveman plugin (§5).

### 5. Claude Code settings — merged into `~/.claude/settings.json`

The installer deep-merges these (your other settings are preserved):

| Key | Value | Effect |
|-----|-------|--------|
| `statusLine.command` | `bash ~/.claude/statusline.sh` | wires up §4 |
| `theme` | `dark` | Claude Code UI theme |
| `tui` | `fullscreen` | full-screen TUI |
| `effortLevel` | `xhigh` | max reasoning effort |
| `model` | `opus[1m]` | Opus 4.x with the 1M-context window |
| `autoCompactEnabled` | `true` | auto-compact long sessions |

**Two things the installer does NOT do automatically:**

- **`[CAVEMAN]` badge / caveman mode** — needs the caveman plugin. In Claude Code: `/plugin` → add marketplace `JuliusBrussee/caveman` → enable `caveman`. Restart. The statusline then shows the badge on its own.
- **⚠️ `permissions.defaultMode: bypassPermissions`** — this is the "**bypass permissions on**" line in the screenshot. It **auto-approves every tool call with no prompt** — Claude can edit files, run any shell command, and call any tool without asking. That is a real risk; only enable it if you understand it and trust your workflow. It is **off unless you pass `--bypass`** to the installer, or set it yourself:
  ```bash
  # opt-in, your call:
  bash ~/.claude-tools/cmux/install.sh --bypass
  ```
  Toggle it live anytime in Claude Code with **Shift+Tab** (cycles permission modes).

---

## Terminal database client (TUI)

For poking at a database from the terminal — fitting the cmux/`fresh` aesthetic — install one of these and use the `db-tui` launcher.

- **[harlequin](https://harlequin.sh)** *(recommended)* — a full SQL IDE in the terminal: results grid, schema tree, query history, autocomplete; one tool for **Postgres, SQLite, MySQL, DuckDB**, and more.
  ```bash
  brew install harlequin            # or: pipx install 'harlequin[postgres]'
  ```
- **[lazysql](https://github.com/jorgerojas26/lazysql)** — lighter, vim-style TUI browser (Postgres/MySQL/SQLite). `brew install lazysql`.
- CLI-with-autocomplete alternatives: `pgcli`, `litecli`, `usql`.

**`db-tui`** opens your client in a **right-side cmux split** anchored to the current workspace (and runs inline when you're not in cmux):

```bash
db-tui 'postgres://user:pass@host:5432/db'   # explicit URL
DATABASE_URL='postgres://…' db-tui           # from the env
DB_CLIENT=lazysql db-tui                      # force a client
```

It auto-picks the first installed client (harlequin → lazysql → pgcli → litecli → usql).

---

## Uninstall / revert

Every file the installer writes is backed up next to it as `<file>.bak-<timestamp>`. To revert a piece, restore its newest `.bak-*`:

```bash
ls -t ~/.config/ghostty/config.bak-*    | head -1   # newest backup
ls -t ~/.claude/settings.json.bak-*     | head -1
# cp the one you want back over the live file, then: cmux reload-config
rm ~/.local/bin/db-tui                              # remove the launcher
```
