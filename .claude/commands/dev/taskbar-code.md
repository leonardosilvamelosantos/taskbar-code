---
description: Carrega o contexto de desenvolvimento do Task Bar Hero e retoma o trabalho de onde parou
argument-hint: "[instrução opcional de retomada]"
---

# Dev — Task Bar Hero

@.claude/context/00-brief.md
@.claude/context/30-active.md

## Contexto sob demanda

Os arquivos abaixo **não** estão carregados. Leia com `Read` apenas o que a tarefa exigir:

- `.claude/context/10-trd.md` — TRD: requisitos, arquitetura, decisões de design, fora de
  escopo. Leia antes de mudar arquitetura ou quando houver dúvida sobre a intenção original.
- `.claude/context/20-roadmap.md` — fases, tarefas e checkpoints (Fases 1-3 concluídas,
  Fase 4 é uma lista de candidatos não priorizados). Leia ao planejar o próximo passo.
- `.claude/context/90-decisions.md` — decisões com razão e tentativas que já falharam
  (BOM, race condition, path matching, DPI, tempo monotônico). Leia antes de propor uma
  abordagem "nova" para um problema já atacado — em particular, a entrada sobre match de
  hook por caminho: já foi tentado por substring e por igualdade exata, os dois falharam
  de formas diferentes antes da versão com normalização funcionar.
- `.claude/context/_archive/` — vazio por ora (nenhuma fase precisou ser arquivada ainda).
- `.claude/context/.last-session.json` — se existir, a sessão anterior terminou sem
  handoff; o estado ativo pode estar defasado. Aponta para o transcript.

## Como começar

1. Confirme o entendimento em 3-5 linhas: fase atual, próximo passo, bloqueios.
2. Se `$ARGUMENTS` trouxer instrução de retomada, ela tem prioridade sobre o próximo passo
   registrado.
3. Se não houver instrução clara, pergunte ao usuário o que ele quer da lista de
   candidatos da Fase 4 antes de implementar qualquer coisa.
4. Qualquer mudança em `install.ps1`/`uninstall.ps1` precisa ser testada contra o
   `settings.json` real do usuário (com backup antes) — nunca só por leitura de código.
   Scripts `.ps1` são ASCII-only (sem acento/em-dash) — já causou 2 quebras de sintaxe
   nesta sessão por causa do parser do PowerShell 5.1 sem BOM.
5. Não recarregue contexto que não vai usar — a janela é o recurso escasso.

$ARGUMENTS
