# Instalação

Este documento é escrito para ser seguido por **um agente Claude Code** que
acabou de clonar este repositório e foi instruído a instalar o Task Bar Hero
— não só por um humano lendo passo a passo. Se você é o agente: siga as
seções na ordem, rode os comandos de verificação indicados, e não invente
caminhos ou nomes de arquivo além dos citados aqui.

## Caminho rápido

Na raiz do repositório clonado:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1 -Yes
```

Use sempre `-Yes` ao instalar de forma autônoma/não-interativa (é o caso de
um agente rodando isso via ferramenta de shell): sem esse flag, se o usuário
tiver um `/statusline` customizado compatível, o script pergunta antes de
aplicar o patch opcional — e um console não-interativo não consegue
responder a esse prompt. O script já trata isso com segurança (não trava,
só pula o patch com aviso), mas `-Yes` evita a ambiguidade.

Isso detecta Python/Node/bash, registra os hooks, cria o atalho de autostart
e já sobe o widget. Se der certo, pule para "Verificação" e pare por aí.

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
| bash | `bash --version` — usado no campo `"shell"` dos hooks registrados; sem ele os hooks falham silenciosamente | Avise o usuário. Sugestão: `winget install -e --id Git.Git` (traz o Git Bash). `install.ps1` já checa isso e só avisa (não bloqueia a instalação). |

Não prossiga além disto se Windows/Python/Node faltarem — reporte o que
falta ao usuário em vez de tentar contornar. A ausência de `bash` é só um
aviso, não um bloqueio (a instalação continua, mas os hooks não vão disparar
até o usuário instalar o Git for Windows).

## O que precisa existir para o widget funcionar

Não é preciso copiar nada para `~/.claude` — o hook e o `ticker.pyw` podem
rodar direto de onde o repositório foi clonado. Só duas coisas precisam
acontecer:

### 1. Hooks registrados em `~/.claude/settings.json`

O arquivo tem uma chave `hooks` cujo formato já deve lhe ser familiar (é o
mecanismo padrão de hooks do Claude Code). Para cada um destes eventos —
`UserPromptSubmit`, `SessionStart`, `SessionEnd`, `PreToolUse`,
`PostToolUse`, `Notification`, `Stop`, `SubagentStop` — garanta que existe
**pelo menos um** grupo cujo `command` contenha o caminho absoluto para
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
normalize e compare o caminho** (não um match de substring solto) —
extraia o trecho entre aspas do `command` de cada entrada já existente
naquele evento, expanda um eventual `$HOME` literal para o valor real,
unifique separadores de caminho (`/` vs `\`), e só então compare com o
caminho absoluto do hook deste repo. Se bater, pule aquele evento. Se não
bater com nenhuma entrada existente, adicione. Nunca remova ou substitua
hooks que já estavam lá para outras finalidades — e nunca use um match por
puro nome de arquivo (`taskbar-hero-update.js` sem o caminho completo):
isso confundiria instalações vindas de clones diferentes do mesmo repo.

Se `settings.json` não existir ainda, crie um novo só com esses hooks. Se
existir, faça um merge cirúrgico (leia com `Read`, edite com `Edit`/`Write`,
ou use `install.ps1` que já faz isso) — e **faça uma cópia de backup do
arquivo antes de reescrevê-lo** (`settings.json.bak`), já que é o arquivo de
configuração central do usuário.

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
autostart no login, crie um atalho `.lnk` chamado **`ClaudeTaskbarHero.lnk`**
em `shell:startup`
(`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup`) apontando para
esse comando — `install.ps1` já faz isso via `WScript.Shell` COM, disponível
nativamente em qualquer PowerShell (não precisa de `pywin32`). Se você já
rodar `install.ps1`, ele também **encerra qualquer instância antiga** do
`ticker.pyw` (por linha de comando via WMI) antes de subir a nova — isso é
esperado, não é um bug se a janela "piscar" ao reinstalar.

## Opcional: patch do `/statusline`

Só relevante se o usuário já tiver um `statusLine.command` customizado em
`settings.json` (verifique lá). Se tiver, e o script apontado ainda não
contiver o marcador de texto `Task Bar Hero`, você pode oferecer inserir o
conteúdo de `statusline-patch.snippet.js` logo antes da última chamada de
`process.stdout.write` naquele arquivo — isso alimenta o anel externo (uso do
rate-limit de 5h) do widget. **Sempre faça um backup `.bak` antes de tocar
num arquivo do usuário**, e pergunte antes de aplicar se estiver rodando de
forma interativa (em modo não-interativo, pule com aviso em vez de travar
esperando uma resposta). Se o usuário não tiver `/statusline` customizado,
pule — o widget funciona normalmente, só o anel de 5h fica vazio.

**Depois de aplicar o patch**, valide antes de reportar sucesso:
1. `node --check "<caminho_do_statusline>"` — confirma que a sintaxe
   continua válida. Se falhar, restaure o `.bak` imediatamente.
2. Confirme que `~/.claude/taskbar-hero/usage.json` passa a ganhar uma
   entrada para a sessão atual depois que o `/statusline` rodar de novo.

## Verificação

Rode estes comandos e confirme os resultados esperados antes de dizer ao
usuário que terminou. Os exemplos abaixo são em PowerShell — **não use
`echo | node ...`**: o `echo` do PowerShell injeta um BOM (U+FEFF) no início
do stdin, e isso faz o `JSON.parse` do hook falhar silenciosamente (exit
code 0, mas nada é escrito). Escreva o JSON num arquivo temporário primeiro.

1. **Hook responde e escreve estado**:
   ```powershell
   [System.IO.File]::WriteAllText("$env:TEMP\tbh-verify.json", '{"session_id":"verify-test","cwd":"C:\\test","hook_event_name":"SessionStart"}', (New-Object System.Text.UTF8Encoding($false)))
   Get-Content "$env:TEMP\tbh-verify.json" -Raw | node hooks\taskbar-hero-update.js
   ```
   (`Out-File -Encoding utf8NoBOM` só existe no PowerShell 7+; em PowerShell
   5.1 use `[System.IO.File]::WriteAllText` como acima, senão o arquivo sai
   com BOM e cai no mesmo bug.)
   Depois confira que `~/.claude/taskbar-hero/sessions/verify-test.json`
   existe e tem conteúdo. Remova esse arquivo de teste depois (é um arquivo
   por sessão, não precisa editar um JSON compartilhado).

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

## Se algo der errado

- **`install.ps1` lança uma exceção no meio**: o script já cobre os casos
  conhecidos (JSON inválido em `settings.json`, console não-interativo,
  `settings.json.bak` sempre criado antes de reescrever). Se mesmo assim
  falhar em algo não previsto, leia a mensagem de erro — ela deve dizer
  exatamente qual etapa falhou (Python, Node, hooks, atalho, ou o processo).
- **Hook nunca dispara** (nenhum arquivo aparece em
  `~/.claude/taskbar-hero/sessions/`): confira se `bash` está instalado
  (tabela de pré-requisitos acima) — os hooks são registrados com
  `"shell": "bash"`.
- **`ticker.pyw` sobe mas a janela não aparece**: pode ser posição salva
  fora da tela atual (monitor externo desconectado) — apague
  `~/.claude/taskbar-hero/window_config.json` e reinicie o processo; ele
  recalcula uma posição padrão ancorada na barra de tarefas.
- **Erro de permissão ao gravar `settings.json`**: confira se o arquivo não
  está aberto/travado por outro processo, ou marcado como somente leitura.

### Desfazer manualmente (se `uninstall.ps1` não servir)

1. Encerre qualquer processo `pythonw.exe`/`python.exe` cuja linha de
   comando contenha `ticker.pyw`.
2. Apague o atalho **`ClaudeTaskbarHero.lnk`** em
   `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup`.
3. Em `~/.claude/settings.json`, remova qualquer objeto de hook cujo
   `command` contenha `taskbar-hero-update.js` (não remova os outros hooks
   do mesmo evento).
4. Se o patch do `/statusline` foi aplicado, restaure o arquivo
   `<statusline>.js.bak` criado ao lado dele — **isso não é revertido
   automaticamente**, nem pelo `uninstall.ps1`.
5. Opcionalmente apague `~/.claude/taskbar-hero/` (estado runtime: posição
   da janela, status por sessão, uso, log).
