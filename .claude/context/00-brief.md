# Task Bar Hero — brief

**O que é:** widget flutuante para Windows, ancorado perto da barra de tarefas e sempre no
topo, que mostra em tempo real o que cada sessão do Claude Code está fazendo (pulso animado
de estado, nome real da aba do Warp, subagentes ativos, uso de contexto/rate-limit). Repo
público: https://github.com/leonardosilvamelosantos/taskbar-code

**Stack:** Python 3 (`tkinter` + `ctypes` + `sqlite3`, tudo stdlib) para o widget; Node.js
(stdlib puro, sem deps) para o hook que alimenta o estado; PowerShell 5.1 para instalação.

**Como rodar**
```
powershell -ExecutionPolicy Bypass -File install.ps1 -Yes   # instala + sobe o widget
python ticker.pyw                                           # rodar com console p/ debug
node -c hooks/taskbar-hero-update.js                        # lint do hook
powershell -ExecutionPolicy Bypass -File uninstall.ps1 -Yes # desinstala
```
Sem test suite automatizada — validação é sempre manual/funcional (ver `90-decisions.md`
para o padrão de teste usado a cada mudança: backup do `settings.json` real, rodar, checar
hash/JSON, restaurar).

**Estrutura**
- `ticker.pyw` — o widget (single-file, ~800 linhas)
- `hooks/taskbar-hero-update.js` — hook do Claude Code, escreve estado por sessão
- `install.ps1` / `uninstall.ps1` / `install.cmd` — instalação
- `statusline-patch.snippet.js` + `statusline-patch.md` — patch opcional do `/statusline`
- `INSTALL.md` — contrato de instalação para um AGENTE seguir (não só humano)

**Convenções**
- Scripts `.ps1` só ASCII — acento/em-dash sem BOM quebra o parser do PowerShell 5.1 (já
  aconteceu 2x nesta sessão, ver `90-decisions.md`).
- JSON sempre UTF-8 **sem BOM** (`Set-Utf8NoBom` nos `.ps1`) — `settings.json` do Claude Code
  não tolera BOM.
- Toda mudança em `install.ps1`/`uninstall.ps1` é testada contra o `settings.json` REAL do
  usuário (com backup antes), nunca só por leitura.

<!-- Teto: 40 linhas. -->
