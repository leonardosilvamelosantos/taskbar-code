# Changelog

## v1.1

- Instalador (`install.ps1`) e desinstalador (`uninstall.ps1`) que funcionam
  em qualquer PC Windows: detectam Python (com Tkinter) e Node.js, mesclam
  os hooks em `~/.claude/settings.json` sem duplicar nem apagar hooks
  existentes do usuário, criam o atalho de autostart sem depender de
  `pywin32`, e sobem o widget imediatamente.
- `INSTALL.md`: contrato de instalação documentado para ser seguido por um
  agente (Claude Code), não só por um humano — cobre pré-requisitos, o
  formato exato do merge em `settings.json` e uma checklist de verificação.
- Checagem de plataforma no topo do `ticker.pyw` (mensagem clara em vez de
  stack trace confuso fora do Windows).
- Revisão de simplificação (reuso/simplificação/eficiência/altitude):
  cache de `usage.json` por ciclo de poll em vez de reler a cada frame do
  slide (~30fps), helper único para "achar bloco por sessionId", remoção de
  parâmetro morto (`color_override`) e de constantes não usadas, e correção
  de um bug real (`_draw_frame(STATE_IDLE)` redundante no `__init__` estava
  sobrescrevendo o estado inicial correto).
- Hook: evita podar o mapa de agentes em `SessionStart` (resultado era
  descartado mesmo), troca um `sort` por `reduce` para achar o agente mais
  recente, e compartilha a forma base do objeto de agente entre os ramos
  `running`/`done`.

## v1.0

- Widget flutuante ancorado na barra de tarefas do Windows, sempre no topo,
  mostrando o estado (pulso animado), nome e atividade de cada sessão do
  Claude Code.
- Nome real da aba do Warp (lido do `warp.sqlite`, casado por
  `WARP_TERMINAL_SESSION_UUID`), com fallback para o título da conversa
  (`aiTitle`), nome derivado da sessão, e por fim a pasta.
- Ícone de robô para subagentes (`Agent` tool), com contador quando há mais
  de um rodando ao mesmo tempo na mesma sessão.
- Anel duplo de uso: contexto por sessão (anel interno) e rate-limit de 5h
  global da conta (anel externo, sempre o valor mais recente entre as
  sessões), com as mesmas cores/thresholds do `/statusline`.
- Carrossel entre terminais com barra de "stories" quando há mais de uma
  sessão ativa.
- Arrastável e redimensionável, com posição persistida.
