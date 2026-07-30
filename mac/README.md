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

## Why not the floating widget?

A floating, always-on-top window that docks near the macOS menu bar / Dock is
possible, but it needs a full rewrite against Cocoa (e.g. `rumps` for a menu-bar
app, or `pyobjc` for `NSWindow` level + `NSWindowCollectionBehavior`). That's a
separate, larger effort. The statusline covers the core value today with zero
extra dependencies. A native menu-bar version is a good follow-up PR.
