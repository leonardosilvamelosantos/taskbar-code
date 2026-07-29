# Changelog

## v1.2

Correções encontradas por uma revisão de gaps com 4 agentes em paralelo
(portabilidade entre máquinas, robustez do instalador, completude da
documentação, cenários de runtime não testados) — dois bugs confirmados por
execução real, o resto por leitura:

- **Hook**: corrigido BOM (U+FEFF) quebrando `JSON.parse` silenciosamente
  quando o stdin vem de `echo`/pipe do PowerShell (mesma correção que o
  `statusline-command.js` do usuário já tinha).
- **Hook**: trocado o `status.json` compartilhado por um arquivo por sessão
  (`sessions/<sessionId>.json`), eliminando a race condition de
  leitura-modificação-escrita entre terminais diferentes; um lock via
  `mkdir` cobre o caso de dois eventos concorrentes na mesma sessão (ex:
  vários subagentes em paralelo).
- **Nova feature**: rastreamento de comandos em segundo plano
  (`run_in_background`, ex. Bash). Antes, quando o Claude parava de gerar
  enquanto ainda esperava um comando em background terminar, o widget dizia
  "Aguardando novo prompt" — sugerindo estar ocioso quando na verdade
  seguia trabalhando. Agora mostra "Aguardando em 2º plano: `<comando>`",
  e o indicador de pulso continua verde/trabalhando nesse caso.
- **`install.ps1`/`uninstall.ps1`**: `Read-Host` não trava mais em sessão
  não-interativa (antes lançava exceção terminante e abortava a instalação
  no meio); match de hook por caminho absoluto normalizado (antes por
  substring solto do nome do arquivo, o que causava falso positivo entre
  clones diferentes do repo — e a primeira correção causou o problema
  oposto, duplicar hooks já registrados com grafia de caminho diferente);
  backup automático de `settings.json` antes de qualquer reescrita; erro
  claro (em vez de stack trace crua) se `settings.json` estiver corrompido;
  checagem de `bash` (necessário pelo `"shell": "bash"` dos hooks
  registrados); verificação pós-start do processo do ticker; patch do
  `/statusline` agora valida com `node --check` e reverte sozinho se
  quebrar a sintaxe; `Unblock-File` nos arquivos do repo (Mark of the Web
  de downloads via ZIP); novo `install.cmd` para clique-duplo.
- **`ticker.pyw`**: DPI-awareness (corrige posição/nitidez em telas com
  escala != 100%, o padrão de fábrica na maioria dos notebooks); posição
  salva validada contra a área virtual de tela atual (evita a janela ficar
  invisível para sempre se um monitor externo for desconectado);
  `time.monotonic()` em vez de `time.time()` para os timers do carrossel
  (a barra de progresso não pula mais para 100% instantaneamente depois de
  o PC voltar de suspensão/hibernação); rotação do `ticker.log`; poda do
  cache de títulos de conversa (`_title_cache`) para sessões encerradas;
  `get_taskbar_rect()` não quebra mais se `Shell_TrayWnd` não for
  encontrado.
- Evento `SubagentStop` (já tratado no código do hook) agora também é
  registrado pelo instalador — antes existia só como código morto do ponto
  de vista de instalação.
- `INSTALL.md`: comando de verificação corrigido (o exemplo antigo também
  caía no bug do BOM), pré-requisito de `bash` documentado, seções de
  troubleshooting e "desfazer manualmente" adicionadas.

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
