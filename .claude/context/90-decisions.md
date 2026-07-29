# Log de decisões — Task Bar Hero

Append-only. O mais recente no topo.

---

### 2026-07-29 — Rastreamento de `run_in_background` como mecanismo separado dos agentes
**Contexto:** usuário reportou sessão mostrando "Aguardando novo prompt" enquanto na
verdade esperava um `npm run build` em segundo plano terminar — texto enganoso.
**Escolha:** novo dict `background{}` no hook, paralelo a `agents{}`, populado só no
`PreToolUse` de qualquer tool (exceto `Agent`) com `tool_input.run_in_background === true`.
TTL de 30min (não 12s como agentes) como rede de segurança, já que não há evento confiável
de "terminou" (o `PostToolUse` do próprio comando confirma só que ele COMEÇOU a rodar em
2º plano, não que finalizou).
**Descartado:** unificar com `agents{}` — os dois têm semânticas de conclusão diferentes
(agente tem stats reais de conclusão; background não tem sinal de conclusão nenhum), forçar
o mesmo shape esconderia essa diferença real.

---

### 2026-07-29 — Arquivo por sessão em vez de `status.json` compartilhado
**Contexto:** revisão de gaps encontrou race condition real: dois terminais disparando
hooks quase simultaneamente podiam se sobrescrever (leitura-modificação-escrita do mesmo
arquivo, sem lock).
**Escolha:** `~/.claude/taskbar-hero/sessions/<sessionId>.json`, um arquivo por sessão.
Dentro da MESMA sessão (ex: subagentes concorrentes), lock via `mkdir` (atômico no
filesystem) com retry curto.
**Razão:** elimina a race ENTRE terminais sem precisar de lock nenhum (cada processo só
toca o próprio arquivo); o lock só cobre o caso residual (mesma sessão, hooks concorrentes).

---

### 2026-07-29 — ❌ Tentativa que falhou: match de hook por caminho absoluto exato
**O que tentamos:** trocar o match por substring solto (`*taskbar-hero-update.js*`) por
comparação exata contra `$HookPath` resolvido, pra evitar falso positivo entre clones do
repo em pastas diferentes.
**Por que falhou:** o `settings.json` real já tinha uma entrada registrada manualmente
antes (nesta mesma sessão de trabalho, num commit anterior) com a grafia
`"$HOME/Documents/Projetos/taskbar-code/hooks/..."` (estilo POSIX, `$HOME` literal). O
match exato contra o caminho Windows resolvido (`C:\Users\...`) não reconheceu como "o
mesmo hook", e o instalador ADICIONOU uma segunda entrada duplicada — confirmado rodando
de verdade contra o `settings.json` real (não só por leitura).
**Não repetir a menos que:** a normalização de caminho (expandir `$HOME`, unificar barras)
seja aplicada ANTES da comparação — é o que a versão final faz (`Get-HookCommandPath` em
`install.ps1`/`uninstall.ps1`).

---

### 2026-07-29 — BOM (U+FEFF) quebrando `JSON.parse` do hook silenciosamente
**Contexto:** revisão de gaps testou o comando de verificação do `INSTALL.md`
(`echo '...' | node hooks/...`) de verdade e descobriu que retornava exit code 0 sem
escrever nada — `echo` do PowerShell injeta BOM no stdin.
**Escolha:** `raw.replace(/^\uFEFF/, '')` antes de `JSON.parse`, nos dois pontos do hook
que fazem parse (payload do stdin e leitura do arquivo por sessão). Mesmo padrão que
`statusline-command.js` do usuário já usava (`raw.replace(/^﻿/, "")`).
**Razão:** o hook já falhava silenciosamente por design (`try/catch` -> `process.exit(0)`
em qualquer erro) — sem essa correção, TODO hook disparado via `echo`/pipe do PowerShell
morre sem deixar rastro.

---

### 2026-07-29 — DPI awareness (`SetProcessDpiAwareness`) antes de criar o `Tk()`
**Contexto:** revisão de gaps apontou que sem isso, em qualquer PC com escala != 100%
(padrão de fábrica na maioria dos notebooks Windows), `GetWindowRect`/`geometry()` ficam
dessincronizados da tela real — texto borrado, posição errada.
**Escolha:** `ctypes.windll.shcore.SetProcessDpiAwareness(2)` com fallback para
`SetProcessDPIAware()` (Windows mais antigo), logo no topo do módulo.
**Descartado:** nada — sem custo/trade-off conhecido, só precisa rodar antes do `tk.Tk()`.

---

### 2026-07-29 — `time.monotonic()` em vez de `time.time()` para timers do carrossel
**Contexto:** `time.time()` (relógio de parede) inclui todo o tempo em que o PC ficou
suspenso/hibernando — o progresso do carrossel saltava pra 100% instantaneamente ao acordar.
**Escolha:** `time.monotonic()` para `hold_started`/`slide_t0` e os cálculos de progresso
derivados deles. `fmt_elapsed()` (tempo decorrido desde a última atualização real, exibido
ao usuário) permanece em `time.time()` de propósito — ali o relógio de parede é o correto.
**Razão:** `monotonic()` é literalmente o propósito dessa API (medir duração, não hora).

---

### 2026-07-29 — Menu Iniciar/Central de Ações do Windows: aceito como limitação permanente
**Contexto:** usuário pediu para o widget sobrepor "tudo, custe o que custar, mesmo com
permissões extra".
**Escolha:** tentado `SetWindowBand` (API não documentada, banda `ZBID_SYSTEM_TOOLS`) para
flyouts comuns (volume, rede) — funciona parcialmente. Menu Iniciar/Central de Ações NÃO
são vencíveis por nenhuma API de janela comum.
**Razão:** essas superfícies do shell rodam numa banda de z-order exclusiva por design de
segurança do Windows (evita apps forjarem/cobrirem UI do sistema) — nem ferramentas
consagradas (Rainmeter) conseguem. Contornar isso exigiria manipulação de DWM/driver, fora
de escopo para um script Python/PowerShell.

<!-- Teto: 150 linhas. -->
