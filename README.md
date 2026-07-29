# Task Bar Hero

Widget flutuante para Windows que mostra, em tempo real, o que cada sessão do
[Claude Code](https://claude.com/claude-code) está fazendo — ancorado perto da
barra de tarefas, sempre no topo, com um carrossel entre terminais quando há
mais de uma sessão ativa.

## O que ele mostra

- **Indicador de pulso** (bolinha à esquerda): verde pulsando = trabalhando,
  amarelo = esperando sua resposta, cinza vazado = ocioso.
- **Nome do terminal**: prioriza o nome que você deu à aba no Warp (lido
  direto do `warp.sqlite`), depois o título da conversa gerado pelo Claude
  Code, depois um nome derivado, depois a pasta.
- **Status + tempo decorrido**: ex. "Executando Bash · 12s".
- **Ícone de robô**: aparece quando um subagente está rodando naquela sessão;
  mostra o tipo do agente e descrição, ou as estatísticas de conclusão
  (tool uses / tokens / tempo). Com múltiplos agentes concorrentes, mostra um
  contador.
- **Anel duplo de uso**: anel interno = % de contexto da conversa (por
  sessão), anel externo = % do rate limit de 5h (global da conta — sempre o
  valor mais recente entre todas as sessões). Mesmas cores/thresholds do
  `/statusline` (verde <50%, amarelo <70%, vermelho daí pra cima).
- **Barra de "stories"** embaixo, tipo Instagram, indicando quantos terminais
  existem e quando vai trocar para o próximo.

## Arquitetura

```
Claude Code hooks (PreToolUse/PostToolUse/Notification/Stop/...)
        │  stdin JSON
        ▼
hooks/taskbar-hero-update.js  ──►  ~/.claude/taskbar-hero/status.json
                                     (por sessionId: cwd, tool, summary,
                                      agents{}, warpUuid)

statusline-command.js (já existente do usuário, com um pequeno acréscimo)
        ▼
~/.claude/taskbar-hero/usage.json   (por sessionId: contextPct, sessionPct)

~/.claude/sessions/<pid>.json       (já existente do Claude Code: status
                                      busy/idle, cwd, name)

warp.sqlite (do próprio Warp)       (nome real da aba, casado por
                                      WARP_TERMINAL_SESSION_UUID)
        │
        ▼
ticker.pyw  ──►  janela tkinter, poll a cada 1s (dados) / 4s (Warp) /
                 60ms (reafirma topmost), desenho 100% em Canvas puro.
```

Não há build step nem dependências externas — só a stdlib do Python 3
(`ctypes`, `sqlite3`, `tkinter`, `json`, `glob`, `os`, `time`, `math`,
`pathlib`) e do Node (`fs`, `path`, `os`). Nenhum `pip install`/`npm install`
necessário.

## Instalação

**Requisitos**: Windows 10/11, Python 3.x com Tkinter, Node.js.

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

Isso detecta Python/Node automaticamente, mescla os hooks no seu
`~/.claude/settings.json` (sem apagar hooks que você já tinha), oferece
aplicar o patch do `/statusline` se você tiver um customizado, cria o atalho
de inicialização automática e já sobe o widget. Rodar de novo não duplica
nada (idempotente). Para desinstalar:

```powershell
powershell -ExecutionPolicy Bypass -File uninstall.ps1
```

Se você é um agente (Claude Code) instalando isto para alguém, ou se o
script não servir no seu ambiente, veja **`INSTALL.md`** — documenta o
contrato exato por trás do script (formato do merge em `settings.json`,
onde cada coisa precisa existir, checklist de verificação) para reproduzir
manualmente.

Veja `CHANGELOG.md` para o histórico de versões.

## Limitações conhecidas

- O menu Iniciar e a Central de Ações do Windows rodam numa camada do shell
  que fica sempre acima de qualquer janela "always on top" comum, por design
  de segurança do Windows — nenhum app (nem ferramentas consagradas como o
  Rainmeter) consegue sobrepor isso de forma confiável sem assinatura de
  código + manifesto UIAccess.
- `warp.sqlite` é um schema interno do Warp, não documentado/sem contrato —
  o código já degrada graciosamente (cai pro nome derivado) se o schema
  mudar ou o Warp não estiver rodando.

## Menu de contexto (clique direito no widget)

- Pausar/retomar o carrossel
- Resetar posição (volta a ancorar automaticamente perto da barra de tarefas)
- Sair
