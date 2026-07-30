#!/usr/bin/env bash
# Task Bar Hero — macOS floating widget installer
# ---------------------------------------------------------------------------
# Installs the floating always-on-top widget (mac/ticker_mac.py):
#   * copies the widget + the state hook into ~/.claude/taskbar-hero/
#   * merges the hook into ~/.claude/settings.json (8 events, idempotent)
#   * installs + loads a LaunchAgent so it starts at login and survives crashes
#   * launches it immediately
# Idempotent — safe to re-run. Requires python3 with tkinter and node.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST_DIR="$CLAUDE_DIR/taskbar-hero"
SETTINGS="$CLAUDE_DIR/settings.json"
AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST="$AGENTS_DIR/ai.claude.taskbar-hero.plist"
LABEL="ai.claude.taskbar-hero"
LOG="$DEST_DIR/agent.log"

echo "==> Task Bar Hero (macOS floating widget)"

# 1. deps -------------------------------------------------------------------
if [ "$(uname)" != "Darwin" ]; then
  echo "ERROR: this installer targets macOS. On Linux run ticker_mac.py directly." >&2
  exit 1
fi
PYTHON="$(command -v python3 || true)"
[ -n "$PYTHON" ] || { echo "ERROR: python3 not found. Install it (brew install python)." >&2; exit 1; }
if ! "$PYTHON" -c "import tkinter" >/dev/null 2>&1; then
  echo "ERROR: python3 lacks tkinter. Install a python3 with Tk (brew install python-tk)." >&2
  exit 1
fi
command -v node >/dev/null 2>&1 || { echo "ERROR: node not found (needed by the state hook)." >&2; exit 1; }
echo "    python3: $PYTHON ($("$PYTHON" -V 2>&1))"
echo "    node:    $(command -v node) ($(node -v))"

# 2. copy widget + hook -----------------------------------------------------
mkdir -p "$DEST_DIR"
cp "$HERE/ticker_mac.py" "$DEST_DIR/ticker_mac.py"
cp "$HERE/../hooks/taskbar-hero-update.js" "$DEST_DIR/taskbar-hero-update.js"
echo "    installed: $DEST_DIR/ticker_mac.py"
echo "    installed: $DEST_DIR/taskbar-hero-update.js"

# 3. merge state hook into settings.json (idempotent) -----------------------
mkdir -p "$CLAUDE_DIR"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
HOOK_CMD="node \"$DEST_DIR/taskbar-hero-update.js\""
node - "$SETTINGS" "$HOOK_CMD" <<'NODE'
const fs = require("fs");
const [file, cmd] = process.argv.slice(2);
const EVENTS = ["UserPromptSubmit","SessionStart","SessionEnd","PreToolUse",
                "PostToolUse","Notification","Stop","SubagentStop"];
let d = {};
try { d = JSON.parse(fs.readFileSync(file, "utf8") || "{}"); } catch {}
d.hooks = d.hooks || {};
let added = 0;
for (const ev of EVENTS) {
  const groups = (d.hooks[ev] = d.hooks[ev] || []);
  // Skip if our command is already wired for this event (re-run safe).
  const present = JSON.stringify(groups).includes("taskbar-hero-update.js");
  if (present) continue;
  groups.push({ hooks: [{ type: "command", command: cmd }] });
  added++;
}
fs.writeFileSync(file, JSON.stringify(d, null, 2) + "\n");
console.log(`    hooks: wired ${added} event(s) (already present skipped)`);
NODE

# 4. install LaunchAgent ----------------------------------------------------
mkdir -p "$AGENTS_DIR"
sed -e "s|__PYTHON__|$PYTHON|g" \
    -e "s|__SCRIPT__|$DEST_DIR/ticker_mac.py|g" \
    -e "s|__LOG__|$LOG|g" \
    "$HERE/ai.claude.taskbar-hero.plist.template" > "$PLIST"
echo "    installed: $PLIST"

# Reload cleanly: unload an old copy (ignore errors), then bootstrap.
UID_NUM="$(id -u)"
launchctl bootout "gui/$UID_NUM/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST" 2>/dev/null || launchctl load "$PLIST" 2>/dev/null || true
launchctl kickstart -k "gui/$UID_NUM/$LABEL" >/dev/null 2>&1 || true

echo "==> Done. The widget is running (bottom-right, above the Dock) and will"
echo "    start automatically at login. Right-click / ctrl-click it for the menu."
echo "    Restart Claude Code sessions so the state hook feeds live summaries."
