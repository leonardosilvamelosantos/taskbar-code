# Patch para o seu `/statusline`

Se você tem um `statusLine` customizado (Node) em `~/.claude/settings.json`,
adicione este trecho **antes** do `process.stdout.write` final, para
alimentar o anel de uso (contexto / rate-limit) do Task Bar Hero:

```js
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
```

Ajuste os nomes de variável (`data`, `cwd`, `usedPct`, `sessionLimit`) para
os que seu script já usa — o trecho acima assume as mesmas convenções do
statusline de referência: `data` é o JSON recebido no stdin, `usedPct` é
`data.context_window.used_percentage`, `sessionLimit` é
`data.rate_limits.five_hour`.

Se você não tem um `/statusline` customizado, o anel externo (rate limit de
5h) simplesmente fica vazio — o resto do widget funciona normalmente.
