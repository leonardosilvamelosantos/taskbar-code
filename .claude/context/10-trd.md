# TRD — Task Bar Hero

## Problema
Rodando várias sessões do Claude Code em paralelo (múltiplas abas do Warp), não há
visibilidade de qual terminal está ocupado, esperando resposta, ou travado — sem alternar
entre janelas. O usuário queria algo tipo "ticker de bolsa de valores" sempre visível.

## Objetivo
Widget sempre-no-topo, perto da barra de tarefas, mostrando por terminal: nome real
(escolhido pelo usuário no Warp), estado (trabalhando/esperando você/ocioso), o que está
fazendo agora (tool, subagente), e uso de contexto/rate-limit. Instalável em qualquer PC
Windows por um agente Claude Code seguindo `INSTALL.md`, sem intervenção manual.

## Fora de escopo
- Linux/Mac (usa `ctypes.windll` e o sqlite do Warp em `%LOCALAPPDATA%`).
- Sobrepor o menu Iniciar/Central de Ações do Windows — camada de shell exclusiva, por
  design de segurança do próprio Windows (nem Rainmeter consegue). Ver `90-decisions.md`.
- Terminais que não sejam Warp para o "nome real da aba" — degrada graciosamente para
  `aiTitle`/nome derivado/pasta se o Warp não estiver instalado ou usar outro schema.
- Test suite automatizada (ver `00-brief.md` — validação é sempre manual/funcional).

## Requisitos
| # | Requisito | Aceite (verificável) |
|---|---|---|
| R1 | Mostrar estado por sessão via pulso animado | verde pulsando = busy, amarelo = precisa de resposta, cinza vazado = idle |
| R2 | Nome real da aba do Warp | lido de `warp.sqlite` via `WARP_TERMINAL_SESSION_UUID`; fallback em cascata se ausente |
| R3 | Subagentes visíveis, inclusive concorrentes | ícone de robô + contador quando `agents{}` tem >1 entrada `running` |
| R4 | Tarefas em segundo plano (`run_in_background`) não parecem "idle" | ver R4 abaixo — `background{}` no hook, `derive_state()` no ticker |
| R5 | Anel de uso: contexto (por sessão) e rate-limit 5h (global) | cores/thresholds idênticos ao `/statusline` do usuário (50/70) |
| R6 | Instalável por um agente sem contexto prévio | `INSTALL.md` + `install.ps1` idempotente, testado contra `settings.json` real |
| R7 | Nunca corromper `settings.json` do usuário | backup automático antes de reescrever; match por caminho normalizado, não substring |

## Arquitetura
```
Claude Code hooks (Pre/PostToolUse, Stop, SubagentStop, Notification, ...)
        |  stdin JSON (pode vir com BOM se disparado via echo/pipe do PowerShell!)
        v
hooks/taskbar-hero-update.js
        |  1 arquivo por sessao (nao mais status.json compartilhado — race condition
        |  entre terminais diferentes; lock via mkdir cobre concorrencia DENTRO da
        |  mesma sessao, ex. varios subagentes em paralelo)
        v
~/.claude/taskbar-hero/sessions/<sessionId>.json
   { cwd, warpUuid, event, tool, summary, agents{}, background{}, updatedAt }

statusline-command.js (do usuario, com patch opcional)  -->  usage.json (contextPct, sessionPct)
~/.claude/sessions/<pid>.json (do proprio Claude Code)   -->  status busy/idle, cwd, name
warp.sqlite (do Warp)                                    -->  nome real da aba, por UUID

ticker.pyw: poll 1s (dados) / 4s (nomes do Warp) / 60ms (reafirma topmost),
            desenho 100% em tkinter Canvas puro, sem imagens/libs externas.
```

Prioridade de nome exibido: nome da aba do Warp -> `aiTitle` da conversa -> nome derivado
do Claude Code -> basename do cwd.

`agents{}` (subagentes, tool `Agent`) vs `background{}` (`run_in_background:true` em
qualquer OUTRA ferramenta, tipicamente Bash): dois mecanismos paralelos e deliberadamente
não-unificados por ora — ver `90-decisions.md` sobre por que isso é aceito como dívida.

## Decisões de design
Ver `90-decisions.md` para o histórico completo com razão e tentativas que falharam
(BOM, race condition, path matching, DPI, tempo monotônico). Resumo das mais relevantes:

| Decisão | Alternativas descartadas | Razão |
|---|---|---|
| Arquivo por sessão em vez de `status.json` compartilhado | lock de arquivo único, mutex nomeado do Windows | Elimina a race entre terminais sem dependência externa; casa com o padrão já usado por `~/.claude/sessions/<pid>.json` |
| `time.monotonic()` para timers do carrossel | manter `time.time()` e clampar | `time.time()` salta com suspensão/hibernação/ajuste de relógio; monotonic é o propósito exato da API |
| Match de hook por caminho absoluto normalizado | substring solto do nome do arquivo | Substring solto causa falso positivo entre clones do repo em pastas diferentes |
| PowerShell puro para o instalador (não Python) | instalar Python primeiro, então rodar um installer .py | PowerShell já existe em qualquer Windows sem instalar nada — não pode depender do que está instalando |

## Riscos e incógnitas
- **`warp.sqlite` é schema não documentado do Warp** → mitigado (degrada para fallback se
  colunas/tabelas mudarem), mas pode quebrar silenciosamente em atualização futura do Warp.
- **Sem sinal confiável de "comando em background terminou"** → `background{}` usa TTL de
  30min como rede de segurança, não uma detecção real de conclusão. Ver R4/decisions.
- **`nameSource`/schema de `~/.claude/sessions/<pid>.json`** é interno do Claude Code, sem
  contrato formal — mudança de versão do Claude Code pode quebrar sem aviso.

<!-- Teto: 250 linhas. -->
