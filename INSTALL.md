# Instalação

Este documento é escrito para ser seguido por **um agente Claude Code** que
acabou de clonar este repositório e foi instruído a instalar o Task Bar Hero
— não só por um humano lendo passo a passo. Se você é o agente: siga as
seções na ordem, rode os comandos de verificação indicados, e não invente
caminhos ou nomes de arquivo além dos citados aqui.

## Caminho rápido

Na raiz do repositório clonado:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

Isso detecta Python/Node, registra os hooks, cria o atalho de autostart e já
sobe o widget. Se der certo, pule para "Verificação" e pare por aí.

Se o script falhar (permissão negada, ambiente não-Windows padrão, shell
diferente, etc.), **não desista** — o resto deste documento descreve o
contrato exato por trás do script, para você reproduzir manualmente (via
Read/Edit/Bash) o que ele faria.

## Pré-requisitos e como checar

| Requisito | Comando de checagem | Se faltar |
|---|---|---|
| Windows 10/11 | — (o projeto é Windows-only: usa `ctypes.windll` e o sqlite do Warp) | Pare e avise o usuário — não há suporte a Linux/Mac. |
| Python 3.x com Tkinter | `py -3 -c "import tkinter"` (ou `python -c "import tkinter"`) — sucesso silencioso = OK | Avise o usuário e pare. Sugestão: `winget install -e --id Python.Python.3.12`. Não instale nada sozinho sem perguntar. |
| Node.js | `node --version` | Avise o usuário e pare. Sugestão: `winget install -e --id OpenJS.NodeJS.LTS`. |

Não prossiga além disto se algum pré-requisito faltar — reporte o que falta
ao usuário em vez de tentar contornar.

## O que precisa existir para o widget funcionar

Não é preciso copiar nada para `~/.claude` — o hook e o `ticker.pyw` podem
rodar direto de onde o repositório foi clonado. Só duas coisas precisam
acontecer:

### 1. Hooks registrados em `~/.claude/settings.json`

O arquivo tem uma chave `hooks` cujo formato já deve lhe ser familiar (é o
mecanismo padrão de hooks do Claude Code). Para cada um destes eventos —
`UserPromptSubmit`, `SessionStart`, `SessionEnd`, `PreToolUse`,
`PostToolUse`, `Notification`, `Stop` — garanta que existe **pelo menos um**
grupo cujo `command` contenha o caminho absoluto para
`hooks/taskbar-hero-update.js` deste repositório. Exemplo de um grupo válido
(adicione ao array do evento, não substitua os que já existem):

```json
{
  "hooks": [
    { "type": "command", "command": "node \"<CAMINHO_ABSOLUTO_DO_REPO>\\hooks\\taskbar-hero-update.js\"", "shell": "bash" }
  ]
}
```

Regra de ouro, para não duplicar em reinstalações: **antes de adicionar,
verifique se algum `command` já existente em qualquer grupo daquele evento
contém a substring `taskbar-hero-update.js`** — se sim, pule aquele evento.
Nunca remova ou substitua hooks que já estavam lá para outras finalidades.

Se `settings.json` não existir ainda, crie um novo só com esses hooks. Se
existir, faça um merge cirúrgico (leia com `Read`, edite com `Edit`/`Write`,
ou use `install.ps1` que já faz isso).

**Atenção de encoding**: grave o arquivo em UTF-8 **sem BOM**. Ferramentas
como `Set-Content -Encoding UTF8` do PowerShell 5.1 adicionam BOM por padrão,
o que quebra o parser de JSON do próprio Claude Code. Se for usar
PowerShell, use `[System.IO.File]::WriteAllText($path, $json, (New-Object
System.Text.UTF8Encoding($false)))` em vez de `Set-Content`.

### 2. O widget rodando

```
pythonw.exe "<CAMINHO_ABSOLUTO_DO_REPO>\ticker.pyw"
```

`pythonw.exe` (não `python.exe`) evita abrir uma janela de console. Para
autostart no login, crie um atalho `.lnk` em `shell:startup`
(`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup`) apontando para
esse comando — `install.ps1` já faz isso via `WScript.Shell` COM, disponível
nativamente em qualquer PowerShell (não precisa de `pywin32`).

## Opcional: patch do `/statusline`

Só relevante se o usuário já tiver um `statusLine.command` customizado em
`settings.json` (verifique lá). Se tiver, e o script apontado ainda não
contiver o marcador de texto `Task Bar Hero`, você pode oferecer inserir o
conteúdo de `statusline-patch.snippet.js` logo antes da última chamada de
`process.stdout.write` naquele arquivo — isso alimenta o anel externo (uso do
rate-limit de 5h) do widget. **Sempre faça um backup `.bak` antes de tocar
num arquivo do usuário**, e pergunte antes de aplicar se estiver rodando de
forma interativa. Se o usuário não tiver `/statusline` customizado, pule —
o widget funciona normalmente, só o anel de 5h fica vazio.

## Verificação

Rode estes comandos e confirme os resultados esperados antes de dizer ao
usuário que terminou:

1. **Hook responde e escreve estado**:
   ```powershell
   echo '{"session_id":"verify-test","cwd":"C:\\test","hook_event_name":"SessionStart"}' | node hooks\taskbar-hero-update.js
   ```
   Depois confira que `~/.claude/taskbar-hero/status.json` contém uma
   entrada `"verify-test"`. Remova essa entrada de teste depois (edite o
   JSON e apague a chave).

2. **`ticker.pyw` sobe sem erro**: rode `python ticker.pyw` (com console, não
   `pythonw`) por uns 10 segundos e confirme que não imprime traceback nem
   fecha sozinho. Depois encerre e suba a versão real com `pythonw.exe`.

3. **`~/.claude/taskbar-hero/ticker.log` está vazio ou não existe** — esse
   arquivo só recebe conteúdo quando uma exceção acontece dentro do loop de
   animação/polling.

4. **O processo está de pé**: confirme via
   `Get-Process pythonw -ErrorAction SilentlyContinue` (ou equivalente) que
   há um processo `pythonw.exe` com `ticker.pyw` na linha de comando.

Só relate sucesso ao usuário depois desses 4 pontos baterem.
