#!/usr/bin/env bash
# Task Bar Hero — macOS statusline installer
# ---------------------------------------------------------------------------
# Installs the macOS statusline port: copies statusline.js into
# ~/.claude/taskbar-hero/ and wires it as the Claude Code "statusLine".
# Idempotent — safe to run again. Backs up settings.json before editing.
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST_DIR="$CLAUDE_DIR/taskbar-hero"
SETTINGS="$CLAUDE_DIR/settings.json"
SRC="$(cd "$(dirname "$0")" && pwd)/statusline.js"

echo "==> Task Bar Hero (macOS statusline)"

# 1. deps -------------------------------------------------------------------
if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: node not found in PATH. Install Node.js first (brew install node)." >&2
  exit 1
fi
NODE_BIN="$(command -v node)"
echo "    node: $NODE_BIN ($(node -v))"

# 2. copy script ------------------------------------------------------------
mkdir -p "$DEST_DIR"
cp "$SRC" "$DEST_DIR/statusline.js"
chmod +x "$DEST_DIR/statusline.js"
echo "    installed: $DEST_DIR/statusline.js"

# 3. wire statusLine into settings.json (via node, no jq dependency) --------
mkdir -p "$CLAUDE_DIR"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"

CMD="$NODE_BIN \"$DEST_DIR/statusline.js\""
node - "$SETTINGS" "$CMD" <<'NODE'
const fs = require("fs");
const [file, cmd] = process.argv.slice(2);
let d = {};
try { d = JSON.parse(fs.readFileSync(file, "utf8") || "{}"); } catch {}
d.statusLine = { type: "command", command: cmd, padding: 0 };
fs.writeFileSync(file, JSON.stringify(d, null, 2) + "\n");
console.log("    statusLine ->", cmd);
NODE

echo "==> Done. Restart Claude Code (or open a new session) to see the statusline."
