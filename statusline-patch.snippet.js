// Alimenta o Task Bar Hero com uso de contexto / rate limit por sessão.
try {
  const fs = require("fs");
  const path = require("path");
  const os = require("os");
  const dir = path.join(os.homedir(), ".claude", "taskbar-hero");
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, "usage.json");
  let usage = {};
  try { usage = JSON.parse(fs.readFileSync(file, "utf8")); } catch { usage = {}; }
  const sessionId = data.session_id;
  if (sessionId) {
    usage[sessionId] = {
      cwd,
      contextPct: typeof usedPct === "number" ? Math.round(usedPct) : null,
      sessionPct:
        sessionLimit && typeof sessionLimit.used_percentage === "number"
          ? Math.round(sessionLimit.used_percentage)
          : null,
      resetsAt: sessionLimit ? sessionLimit.resets_at : null,
      updatedAt: Date.now(),
    };
    const tmp = file + ".tmp-" + process.pid;
    fs.writeFileSync(tmp, JSON.stringify(usage));
    fs.renameSync(tmp, file);
  }
} catch {}
