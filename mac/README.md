# Task Bar Hero — macOS port (statusline)

> **macOS only.** This is a native-friendly port of Task Bar Hero for macOS.

The original Task Bar Hero (`ticker.pyw`) is a floating, always-on-top Tkinter
widget that depends on Win32 APIs (`ctypes.windll` for z-order, the taskbar
band, and the single-instance mutex). Those calls have **no macOS equivalent**,
so a 1:1 floating-window port isn't practical.

This port keeps the *idea* — live, at-a-glance status of your Claude Code
session — but renders it where macOS makes it easy and reliable: as a Claude
Code **statusline** at the bottom of the terminal.

```
[CAVEMAN] · Opus 4.8 (1M) · my-project (main) · ctx 78% · $1.42 · 35m · +127/-9
```

## What it shows

| Segment      | Source                                             |
|--------------|----------------------------------------------------|
| model        | `model.display_name` from the Status hook payload  |
| dir (branch) | working dir basename + current git branch          |
| ctx NN%      | context **remaining**, read from the session transcript (auto-detects 1M window for `[1m]` models); color shifts green → yellow → red |
| $cost        | `cost.total_cost_usd`                              |
| time         | session duration                                   |
| +add/-del    | lines added / removed this session                 |

The `[CAVEMAN]` badge is optional — it's only shown if you also run the
caveman-mode plugin. Absent → skipped silently.

## Requirements

- macOS
- Node.js (`brew install node`)
- Claude Code

## Install

```bash
bash mac/install.sh
```

It copies `statusline.js` to `~/.claude/taskbar-hero/`, backs up your
`settings.json`, and sets the `statusLine` entry. Idempotent — safe to re-run.
Restart Claude Code (or open a new session) to see it.

## Uninstall

Remove the `statusLine` key from `~/.claude/settings.json` (a timestamped
`settings.json.bak-*` backup is created on install), then delete
`~/.claude/taskbar-hero/`.

## The floating widget (macOS port)

`ticker_mac.py` is a real port of the Windows floating chip (`ticker.pyw`) —
same "Vital Signs" design: animated pulse indicator, 2-line text (session name +
what it's doing), dual metric ring (context / 5h rate limit), and the carousel
bar across terminals. It reads the **same** state files, which are already
cross-platform:

- `~/.claude/sessions/<pid>.json` — written natively by Claude Code (status,
  cwd, name, sessionId)
- `~/.claude/taskbar-hero/sessions/<sid>.json` — written by the shared hook
  (`hooks/taskbar-hero-update.js`) for the "Executando Bash · 1m" style summary
- `~/.claude/taskbar-hero/usage.json` — written by the statusline patch, feeds
  the rings (optional; rings just stay empty without it)

What changed from the Windows build, all platform-forced:

| Windows                                   | macOS port                          |
|-------------------------------------------|-------------------------------------|
| Win32 `SetWindowPos`/`SetWindowBand` z-order | Tk `-topmost`, re-asserted every 2s |
| named kernel mutex (single instance)      | pidfile lock (`ticker.lock`)        |
| `OpenProcess` liveness                    | `os.kill(pid, 0)`                   |
| `Shell_TrayWnd` taskbar anchor            | screen bottom-right, above the Dock |
| Segoe UI / Consolas                       | SF Pro / Menlo (with fallbacks)     |
| Warp sqlite in `%LOCALAPPDATA%`           | Warp sqlite in `~/Library/Application Support` |

### Install (widget + autostart)

```bash
bash mac/install-widget.sh
```

Copies the widget + state hook into `~/.claude/taskbar-hero/`, merges the hook
into `settings.json` (8 events, idempotent, existing hooks preserved), installs
a **LaunchAgent** (`~/Library/LaunchAgents/ai.claude.taskbar-hero.plist`) so it
starts at login and restarts on crash, and launches it immediately.

Requires `python3` with `tkinter` (`brew install python-tk`) and `node`.

Controls: **drag** to move, **ctrl-click / right-click** for the menu
(Pause / Reset position / Quit), resize from the bottom-right corner.

### Run once without autostart

```bash
python3 mac/ticker_mac.py
```

### Uninstall

```bash
bash mac/uninstall-widget.sh
```

## Two ways to run it

- **statusline** (`install.sh`) — zero deps, lives in the terminal footer.
- **floating widget** (`install-widget.sh`) — closest to the Windows original,
  needs python3+tkinter. They're independent; run either or both.

A native menu-bar variant (rumps / pyobjc, docked by the clock) remains a good
follow-up for anyone who wants the chip in the system menu bar instead.
