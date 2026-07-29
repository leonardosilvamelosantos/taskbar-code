# Patch para o seu `/statusline`

Se você tem um `statusLine` customizado (Node) em `~/.claude/settings.json`,
adicione o conteúdo de [`statusline-patch.snippet.js`](statusline-patch.snippet.js)
**antes** do `process.stdout.write` final, para alimentar o anel de uso
(contexto / rate-limit) do Task Bar Hero. `install.ps1` já oferece aplicar
isso automaticamente se detectar um `/statusline` compatível.

Ajuste os nomes de variável (`data`, `cwd`, `usedPct`, `sessionLimit`) para
os que seu script já usa — o trecho acima assume as mesmas convenções do
statusline de referência: `data` é o JSON recebido no stdin, `usedPct` é
`data.context_window.used_percentage`, `sessionLimit` é
`data.rate_limits.five_hour`.

Se você não tem um `/statusline` customizado, o anel externo (rate limit de
5h) simplesmente fica vazio — o resto do widget funciona normalmente.
