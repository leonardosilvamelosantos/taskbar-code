# Estado ativo — Task Bar Hero

**Handoff em:** 2026-07-29 20:20 · **Fase:** 3 concluída, Fase 4 não iniciada · **Progresso:** v1.2 shipado

## Onde paramos
Fase 3 (revisão de gaps com 4 agentes + correções) concluída e enviada — commit `6a084d4`,
já no GitHub público. Última mudança: nova feature de rastreamento de `background{}`
(tarefas `run_in_background`) pra corrigir o texto "Aguardando novo prompt" que aparecia
enganosamente enquanto uma sessão esperava um `npm run build` em segundo plano terminar.
Tudo testado ao vivo contra o `settings.json` real do usuário (instalação do zero,
idempotência, desinstalação) antes de commitar. Nada ficou pela metade.

## Próximo passo
Nenhuma tarefa pendente explícita. Se o usuário voltar sem contexto, pergunte o que ele
quer da lista da Fase 4 (`20-roadmap.md`) — os itens de "altitude" (state explícito no
hook, name-providers genérico) são os de maior valor arquitetural; os de menor prioridade
(monitor secundário, cache do Warp obsoleto após restart, sessões zumbis) são polish.

## Bloqueios / decisões pendentes
- Nenhum bloqueio técnico. Nenhuma decisão pendente de aprovação do usuário.

## Arquivos quentes
- `ticker.pyw` — widget inteiro, ~800 linhas; `derive_state()` e `collect_sessions()` são
  os pontos de extensão mais prováveis pra Fase 4
- `hooks/taskbar-hero-update.js` — hook; `summarize()` concentra toda a lógica de estado
- `install.ps1` / `uninstall.ps1` — cuidado com encoding: só ASCII, sem BOM (ver `90-decisions.md`)
- `.claude/context/20-roadmap.md` — candidatos da Fase 4

## Verificação
- Testes: sem suite automatizada; validação manual contra `settings.json` real a cada
  mudança nos `.ps1` (ver `00-brief.md`) — última rodada: instalação do zero + idempotência
  + desinstalação, todas passaram
- Build: N/A (sem build step — Python/Node stdlib puro)
- Git: limpo, tudo commitado e enviado (`git log -1` = `6a084d4`)
- Runtime: ticker rodando ao vivo na máquina do usuário (PID variável, ver Task Manager),
  `ticker.log` vazio (sem exceções)
