> 🇧🇷 [Leia em português](INSTALL.pt-BR.md)

# Installation

This document is written to be followed by **a Claude Code agent** that just
cloned this repository and was instructed to install Task Bar Hero — not
just by a human reading step by step. If you're the agent: follow the
sections in order, run the verification commands listed, and don't invent
paths or file names beyond the ones mentioned here.

## Quick path

From the root of the cloned repository:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1 -Yes
```

Always use `-Yes` when installing autonomously/non-interactively (this is
the case when an agent runs this via a shell tool): without that flag, if
the user has a compatible custom `/statusline`, the script asks before
applying the optional patch — and a non-interactive console can't answer
that prompt. The script already handles this safely (it doesn't hang, it
just skips the patch with a warning), but `-Yes` removes the ambiguity.

This detects Python/Node/bash, registers the hooks, creates the autostart
shortcut, and starts the widget right away. If it succeeds, skip to
"Verification" and stop there.

If the script fails (permission denied, non-standard Windows environment,
different shell, etc.), **don't give up** — the rest of this document
describes the exact contract behind the script, so you can reproduce
manually (via Read/Edit/Bash) what it would have done.

## Prerequisites and how to check them

| Requirement | Check command | If missing |
|---|---|---|
| Windows 10/11 | — (the project is Windows-only: it uses `ctypes.windll` and Warp's sqlite) | Stop and tell the user — there's no Linux/Mac support. |
| Python 3.x with Tkinter | `py -3 -c "import tkinter"` (or `python -c "import tkinter"`) — silent success = OK | Tell the user and stop. Suggestion: `winget install -e --id Python.Python.3.12`. Don't install anything on your own without asking. |
| Node.js | `node --version` | Tell the user and stop. Suggestion: `winget install -e --id OpenJS.NodeJS.LTS`. |
| bash | `bash --version` — used in the `"shell"` field of the registered hooks; without it the hooks fail silently | Warn the user. Suggestion: `winget install -e --id Git.Git` (brings Git Bash). `install.ps1` already checks this and only warns (doesn't block installation). |

Don't proceed further if Windows/Python/Node are missing — report what's
missing to the user instead of trying to work around it. The absence of
`bash` is just a warning, not a blocker (installation continues, but the
hooks won't fire until the user installs Git for Windows).

## What needs to exist for the widget to work

Nothing needs to be copied into `~/.claude` — the hook and `ticker.pyw` can
run directly from wherever the repository was cloned. Only two things need
to happen:

### 1. Hooks registered in `~/.claude/settings.json`

The file has a `hooks` key whose format should already be familiar to you
(it's Claude Code's standard hooks mechanism). For each of these events —
`UserPromptSubmit`, `SessionStart`, `SessionEnd`, `PreToolUse`,
`PostToolUse`, `Notification`, `Stop`, `SubagentStop` — make sure there is
**at least one** group whose `command` contains the absolute path to this
repository's `hooks/taskbar-hero-update.js`. Example of a valid group (add
it to the event's array, don't replace what's already there):

```json
{
  "hooks": [
    { "type": "command", "command": "node \"<ABSOLUTE_REPO_PATH>\\hooks\\taskbar-hero-update.js\"", "shell": "bash" }
  ]
}
```

Golden rule, to avoid duplicates on reinstall: **normalize and compare the
path before adding** (not a loose substring match) — extract the quoted
portion from each existing entry's `command` in that event, expand any
literal `$HOME` to its real value, unify path separators (`/` vs `\`), and
only then compare against this repo's absolute hook path. If it matches,
skip that event. If it doesn't match any existing entry, add it. Never
remove or replace hooks that were already there for other purposes — and
never match by bare file name (`taskbar-hero-update.js` without the full
path): that would confuse installs coming from different clones of the same
repo.

If `settings.json` doesn't exist yet, create a new one with just these
hooks. If it exists, do a surgical merge (read with `Read`, edit with
`Edit`/`Write`, or use `install.ps1`, which already does this) — and **make
a backup copy of the file before rewriting it** (`settings.json.bak`), since
it's the user's central configuration file.

**Encoding warning**: write the file as UTF-8 **without BOM**. Tools like
PowerShell 5.1's `Set-Content -Encoding UTF8` add a BOM by default, which
breaks Claude Code's own JSON parser. If you're using PowerShell, use
`[System.IO.File]::WriteAllText($path, $json, (New-Object
System.Text.UTF8Encoding($false)))` instead of `Set-Content`.

### 2. The widget running

```
pythonw.exe "<ABSOLUTE_REPO_PATH>\ticker.pyw"
```

`pythonw.exe` (not `python.exe`) avoids opening a console window. For
autostart on login, create a `.lnk` shortcut named
**`ClaudeTaskbarHero.lnk`** in `shell:startup`
(`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup`) pointing to that
command — `install.ps1` already does this via the `WScript.Shell` COM
object, natively available in any PowerShell (no `pywin32` needed). If you
run `install.ps1`, it also **kills any previous instance** of `ticker.pyw`
(by command line, via WMI) before starting the new one — that's expected,
not a bug, if the window "blinks" on reinstall.

## Optional: `/statusline` patch

Only relevant if the user already has a custom `statusLine.command` in
`settings.json` (check there). If they do, and the referenced script doesn't
already contain the text marker `Task Bar Hero`, you can offer to insert the
contents of `statusline-patch.snippet.js` right before the last
`process.stdout.write` call in that file — this feeds the widget's outer
ring (5h rate-limit usage). **Always make a `.bak` backup before touching a
user's file**, and ask before applying if running interactively (in
non-interactive mode, skip with a warning instead of hanging waiting for a
response). If the user doesn't have a custom `/statusline`, skip — the
widget still works normally, only the 5h ring stays empty.

**After applying the patch**, validate before reporting success:
1. `node --check "<statusline_path>"` — confirms the syntax is still valid.
   If it fails, restore the `.bak` immediately.
2. Confirm that `~/.claude/taskbar-hero/usage.json` gains an entry for the
   current session after `/statusline` runs again.

## Verification

Run these commands and confirm the expected results before telling the user
you're done. The examples below are PowerShell — **don't use
`echo | node ...`**: PowerShell's `echo` injects a BOM (U+FEFF) at the start
of stdin, which makes the hook's `JSON.parse` fail silently (exit code 0,
but nothing gets written). Write the JSON to a temp file first.

1. **Hook responds and writes state**:
   ```powershell
   [System.IO.File]::WriteAllText("$env:TEMP\tbh-verify.json", '{"session_id":"verify-test","cwd":"C:\\test","hook_event_name":"SessionStart"}', (New-Object System.Text.UTF8Encoding($false)))
   Get-Content "$env:TEMP\tbh-verify.json" -Raw | node hooks\taskbar-hero-update.js
   ```
   (`Out-File -Encoding utf8NoBOM` only exists in PowerShell 7+; in
   PowerShell 5.1 use `[System.IO.File]::WriteAllText` as above, otherwise
   the file comes out with a BOM and hits the same bug.)
   Then check that `~/.claude/taskbar-hero/sessions/verify-test.json` exists
   and has content. Remove that test file afterward (it's a per-session
   file, no need to edit a shared JSON).

2. **`ticker.pyw` starts without error**: run `python ticker.pyw` (with a
   console, not `pythonw`) for about 10 seconds and confirm it doesn't print
   a traceback or close on its own. Then stop it and start the real version
   with `pythonw.exe`.

3. **`~/.claude/taskbar-hero/ticker.log` is empty or doesn't exist** — this
   file only gets content when an exception happens inside the
   animation/polling loop.

4. **The process is up**: confirm via
   `Get-Process pythonw -ErrorAction SilentlyContinue` (or equivalent) that
   there's a `pythonw.exe` process with `ticker.pyw` in its command line.

Only report success to the user after these 4 checks pass.

## If something goes wrong

- **`install.ps1` throws an exception midway**: the script already covers
  the known cases (invalid JSON in `settings.json`, non-interactive
  console, `settings.json.bak` always created before rewriting). If it
  still fails on something unexpected, read the error message — it should
  say exactly which step failed (Python, Node, hooks, shortcut, or the
  process).
- **Hook never fires** (no file appears in
  `~/.claude/taskbar-hero/sessions/`): check whether `bash` is installed
  (prerequisites table above) — the hooks are registered with
  `"shell": "bash"`.
- **`ticker.pyw` starts but the window doesn't appear**: could be a saved
  position outside the current screen (external monitor disconnected) —
  delete `~/.claude/taskbar-hero/window_config.json` and restart the
  process; it recalculates a default position anchored to the taskbar.
- **Permission error writing `settings.json`**: check whether the file is
  open/locked by another process, or marked read-only.

### Undo manually (if `uninstall.ps1` doesn't work)

1. Kill any `pythonw.exe`/`python.exe` process whose command line contains
   `ticker.pyw`.
2. Delete the **`ClaudeTaskbarHero.lnk`** shortcut in
   `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup`.
3. In `~/.claude/settings.json`, remove any hook object whose `command`
   contains `taskbar-hero-update.js` (don't remove the other hooks for the
   same event).
4. If the `/statusline` patch was applied, restore the
   `<statusline>.js.bak` file created next to it — **this is not reverted
   automatically**, not even by `uninstall.ps1`.
5. Optionally delete `~/.claude/taskbar-hero/` (runtime state: window
   position, per-session status, usage, log).
