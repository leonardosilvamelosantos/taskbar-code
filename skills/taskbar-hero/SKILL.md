---
description: Sobe o widget Task Bar Hero Code se ele nao estiver rodando
---

Inicie o Task Bar Hero Code:

1. Verifique se ja existe um processo `pythonw.exe`/`python.exe` com `ticker.pyw`
   na linha de comando (ex. via `Get-CimInstance Win32_Process` no PowerShell). Se
   existir, avise o usuario que o widget ja esta rodando e pare — nao inicie uma
   segunda instancia (o `ticker.pyw` tem uma guarda de mutex que impediria de
   qualquer forma, mostrando um popup "ja esta em execucao").
2. Caso contrario, rode:
   ```
   pythonw.exe "${CLAUDE_PLUGIN_ROOT}/ticker.pyw"
   ```
3. Confirme que o processo continua de pe um segundo depois (se encerrar
   sozinho, leia `~/.claude/taskbar-hero/ticker.log` para diagnosticar — mesmo
   procedimento do `INSTALL.md` deste repositorio).

Requisitos: Windows 10/11, Python 3.x com Tkinter. Se `pythonw.exe` nao for
encontrado no PATH, avise o usuario e sugira instalar Python (ex.
`winget install -e --id Python.Python.3.12`) antes de tentar de novo.
