#!/usr/bin/env node
/*
 * Task Bar Hero — macOS statusline port
 * ------------------------------------------------------------------
 * The original Task Bar Hero widget (ticker.pyw) is a floating, always-on-top
 * Tkinter window that relies on Win32 APIs (ctypes.windll: z-order, taskbar
 * band, single-instance mutex). Those have no macOS equivalent, so this port
 * takes a different, native-friendly shape: a Claude Code **statusline**.
 *
 * Instead of a floating window it renders a single status row at the bottom of
 * the terminal, fed by the Status hook JSON that Claude Code writes on stdin:
 *
 *   model · dir (git branch) · ctx NN% · $cost · time · +add/-del
 *
 * No external dependencies — Node standard library only.
 * macOS (and Linux) only in spirit; it will run anywhere Node runs.
 *
 * Wire it up in ~/.claude/settings.json (install.sh does this for you):
 *   "statusLine": { "type": "command",
 *                   "command": "node \"$HOME/.claude/taskbar-hero/statusline.js\"" }
 */

const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync } = require("child_process");

// ---- ANSI helpers -----------------------------------------------------------
const C = {
  reset: "\x1b[0m",
  dim: "\x1b[38;5;245m",
  sep: "\x1b[38;5;240m",
  model: "\x1b[38;5;110m",
  dir: "\x1b[38;5;150m",
  git: "\x1b[38;5;180m",
  cost: "\x1b[38;5;114m",
  time: "\x1b[38;5;146m",
  ctxOk: "\x1b[38;5;114m",
  ctxWarn: "\x1b[38;5;179m",
  ctxHot: "\x1b[38;5;203m",
  add: "\x1b[38;5;114m",
  del: "\x1b[38;5;203m",
};
const SEP = `${C.sep} · ${C.reset}`;

// ---- read stdin -------------------------------------------------------------
let raw = "";
try { raw = fs.readFileSync(0, "utf8"); } catch {}
let p = {};
try { p = JSON.parse(raw || "{}"); } catch {}

const segs = [];

// ---- optional caveman badge -------------------------------------------------
// If the user also runs the "caveman mode" plugin, keep its badge in front.
// Purely optional: absent script → skipped silently.
try {
  const cavemanSh = path.join(os.homedir(), ".claude", "hooks", "caveman-statusline.sh");
  if (fs.existsSync(cavemanSh)) {
    const badge = execFileSync("bash", [cavemanSh], {
      input: raw, timeout: 1500, encoding: "utf8",
    }).trim();
    if (badge) segs.push(badge);
  }
} catch {}

// ---- model ------------------------------------------------------------------
const model = p.model && (p.model.display_name || p.model.id);
if (model) segs.push(`${C.model}${model}${C.reset}`);

// ---- dir + git branch -------------------------------------------------------
const cwd = (p.workspace && (p.workspace.current_dir || p.workspace.project_dir)) || process.cwd();
let dirSeg = `${C.dir}${path.basename(cwd)}${C.reset}`;
try {
  const branch = execFileSync("git", ["-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"], {
    timeout: 800, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"],
  }).trim();
  if (branch && branch !== "HEAD") dirSeg += ` ${C.git}(${branch})${C.reset}`;
} catch {}
segs.push(dirSeg);

// ---- context usage from transcript ------------------------------------------
// Model id decides the window. [1m] / -1m variants get a 1M window.
function contextWindow(id) {
  const s = String(id || "");
  if (/\[1m\]|-1m|\b1m\b/i.test(s)) return 1000000;
  return 200000;
}
function readContextPct() {
  const tp = p.transcript_path;
  if (!tp || !fs.existsSync(tp)) {
    // Fallback: the coarse flag Claude Code always provides.
    return p.exceeds_200k_tokens ? { pct: 100, used: null } : null;
  }
  try {
    const lines = fs.readFileSync(tp, "utf8").split("\n");
    // Walk backwards to the most recent assistant usage record.
    for (let i = lines.length - 1; i >= 0; i--) {
      const ln = lines[i].trim();
      if (!ln) continue;
      let obj;
      try { obj = JSON.parse(ln); } catch { continue; }
      const u = obj && obj.message && obj.message.usage;
      if (u) {
        const used =
          (u.input_tokens || 0) +
          (u.cache_read_input_tokens || 0) +
          (u.cache_creation_input_tokens || 0);
        const win = contextWindow((p.model && p.model.id) || model);
        return { pct: Math.min(100, Math.round((used / win) * 100)), used };
      }
    }
  } catch {}
  return null;
}
const ctx = readContextPct();
if (ctx) {
  const remaining = 100 - ctx.pct;
  const col = remaining > 40 ? C.ctxOk : remaining > 15 ? C.ctxWarn : C.ctxHot;
  segs.push(`${col}ctx ${remaining}%${C.reset}`);
}

// ---- cost + duration --------------------------------------------------------
const cost = p.cost || {};
if (typeof cost.total_cost_usd === "number") {
  segs.push(`${C.cost}$${cost.total_cost_usd.toFixed(2)}${C.reset}`);
}
if (typeof cost.total_duration_ms === "number") {
  const mins = Math.floor(cost.total_duration_ms / 60000);
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  const t = h > 0 ? `${h}h${String(m).padStart(2, "0")}m` : `${m}m`;
  segs.push(`${C.time}${t}${C.reset}`);
}

// ---- lines changed ----------------------------------------------------------
const add = cost.total_lines_added || 0;
const del = cost.total_lines_removed || 0;
if (add || del) {
  segs.push(`${C.add}+${add}${C.reset}${C.dim}/${C.reset}${C.del}-${del}${C.reset}`);
}

// ---- emit -------------------------------------------------------------------
process.stdout.write(segs.filter(Boolean).join(SEP));
