# Changelog

## v1.3

- **New**: two more ways to start the widget besides autostart — a Start
  menu shortcut ("Task Bar Hero Code", searchable via the Windows key) and
  a Desktop shortcut, both created by `install.ps1`. Previously the only
  shortcut was in the Startup folder, so closing the widget left no way to
  reopen it short of logging back in or rerunning the installer.
- **New**: a global `/taskbar-hero` Claude Code command
  (`~/.claude/commands/taskbar-hero.md`, installed from
  `commands/taskbar-hero.md.template`) that starts the widget from any
  session, not just one opened in this repository.
- **Fix**: `ticker.pyw` had no protection against a second instance. With
  three easy-to-click entry points now available, this became a real risk
  (duplicate overlapping widgets). Added a named-mutex guard
  (`Global\ClaudeTaskbarHeroCode`) with a short retry — a second launch
  while one is already running shows a message box and exits instead of
  duplicating. The retry also covers the pre-existing install.ps1 reinstall
  race (old process killed and new one started with no pause in between).
- `uninstall.ps1` removes the two new shortcuts and the `/taskbar-hero`
  command alongside what it already removed.

## v1.2

Fixes found by a 4-agent parallel gap review (portability across machines,
installer robustness, documentation completeness, untested runtime
scenarios) — two bugs confirmed by live execution, the rest by reading:

- **Hook**: fixed a BOM (U+FEFF) silently breaking `JSON.parse` when stdin
  comes from a PowerShell `echo`/pipe (same fix the user's
  `statusline-command.js` already had).
- **Hook**: replaced the shared `status.json` with a per-session file
  (`sessions/<sessionId>.json`), eliminating the read-modify-write race
  condition between different terminals; a `mkdir`-based lock covers the
  case of two concurrent events in the same session (e.g. several parallel
  subagents).
- **New feature**: tracking background commands (`run_in_background`, e.g.
  Bash). Previously, when Claude stopped generating while still waiting for
  a background command to finish, the widget said "Waiting for new
  prompt" — suggesting it was idle when it was actually still working. It
  now shows "Waiting on background: `<command>`", and the pulse indicator
  stays green/working in that case.
- **`install.ps1`/`uninstall.ps1`**: `Read-Host` no longer hangs in a
  non-interactive session (previously threw a terminating exception and
  aborted installation midway); hook matching now uses a normalized
  absolute path (previously a loose file-name substring match, which
  caused false positives between different clones of the repo — and the
  first fix caused the opposite problem, duplicating already-registered
  hooks with differently-spelled paths); automatic `settings.json` backup
  before any rewrite; clear error (instead of a raw stack trace) if
  `settings.json` is corrupted; checks for `bash` (required by the
  registered hooks' `"shell": "bash"`); post-start verification of the
  ticker process; the `/statusline` patch now validates with `node --check`
  and self-reverts if it breaks the syntax; `Unblock-File` on the repo's
  files (Mark of the Web from ZIP downloads); new `install.cmd` for
  double-click installs.
- **`ticker.pyw`**: DPI-awareness (fixes position/sharpness on screens with
  scaling != 100%, the factory default on most laptops); saved position
  validated against the current virtual screen area (prevents the window
  from staying invisible forever if an external monitor is disconnected);
  `time.monotonic()` instead of `time.time()` for the carousel timers (the
  progress bar no longer jumps instantly to 100% after the PC wakes from
  sleep/hibernation); `ticker.log` rotation; pruning of the conversation
  title cache (`_title_cache`) for ended sessions;
  `get_taskbar_rect()` no longer crashes if `Shell_TrayWnd` isn't found.
- The `SubagentStop` event (already handled in the hook's code) is now also
  registered by the installer — previously it only existed as dead code
  from an installation standpoint.
- `INSTALL.md`: fixed the verification command (the old example also hit
  the BOM bug), documented the `bash` prerequisite, added troubleshooting
  and "undo manually" sections.

## v1.1

- Installer (`install.ps1`) and uninstaller (`uninstall.ps1`) that work on
  any Windows PC: detect Python (with Tkinter) and Node.js, merge the hooks
  into `~/.claude/settings.json` without duplicating or deleting the user's
  existing hooks, create the autostart shortcut without depending on
  `pywin32`, and start the widget immediately.
- `INSTALL.md`: installation contract documented to be followed by an agent
  (Claude Code), not just a human — covers prerequisites, the exact
  `settings.json` merge format, and a verification checklist.
- Platform check at the top of `ticker.pyw` (clear message instead of a
  confusing stack trace outside Windows).
- Simplification review (reuse/simplification/efficiency/altitude):
  `usage.json` cached per poll cycle instead of re-read on every carousel
  frame (~30fps), a single helper for "find block by sessionId", removal of
  a dead parameter (`color_override`) and unused constants, and a real bug
  fix (a redundant `_draw_frame(STATE_IDLE)` in `__init__` was overwriting
  the correct initial state).
- Hook: avoids pruning the agent map on `SessionStart` (the result was
  discarded anyway), swaps a `sort` for a `reduce` to find the most recent
  agent, and shares the base agent object shape between the
  `running`/`done` branches.

## v1.0

- Floating widget anchored to the Windows taskbar, always on top, showing
  the state (animated pulse), name, and activity of each Claude Code
  session.
- Real Warp tab name (read from `warp.sqlite`, matched via
  `WARP_TERMINAL_SESSION_UUID`), falling back to the conversation title
  (`aiTitle`), a derived session name, and finally the folder.
- Robot icon for subagents (`Agent` tool), with a counter when more than
  one is running at the same time in the same session.
- Double usage ring: per-session context (inner ring) and the account-wide
  5h rate limit (outer ring, always the most recent value across
  sessions), with the same colors/thresholds as `/statusline`.
- Carousel between terminals with a "stories" bar when more than one
  session is active.
- Draggable and resizable, with persisted position.
