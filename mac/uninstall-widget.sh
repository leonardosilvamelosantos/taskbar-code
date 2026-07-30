#!/usr/bin/env bash
# Task Bar Hero — macOS widget uninstaller.
# Unloads + removes the LaunchAgent and stops the widget. Leaves settings.json
# hooks and the installed files in place (remove them by hand if you want a
# full wipe — a settings.json.bak-* backup was made at install time).
set -euo pipefail

LABEL="ai.claude.taskbar-hero"
PLIST="$HOME/Library/LaunchAgents/ai.claude.taskbar-hero.plist"
UID_NUM="$(id -u)"

launchctl bootout "gui/$UID_NUM/$LABEL" >/dev/null 2>&1 || launchctl unload "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"

# Best-effort kill of any lingering instance.
pkill -f "taskbar-hero/ticker_mac.py" >/dev/null 2>&1 || true
rm -f "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/taskbar-hero/ticker.lock"

echo "==> Task Bar Hero widget stopped and LaunchAgent removed."
echo "    To also stop the state hook, remove the taskbar-hero-update.js entries"
echo "    from ~/.claude/settings.json (a .bak-* backup exists from install)."
