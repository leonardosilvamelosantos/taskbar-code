# Roadmap — Task Bar Hero

Sequência de execução. Fases não se sobrepõem: a seguinte só começa após o checkpoint da
anterior passar.

---

## Fase 1 — Widget funcional (v1.0) ✅ concluída
**Meta:** widget rodando na máquina do autor, pulso/nome/agente/anel de uso, carrossel.

- [x] `ticker.pyw` — design "Vital Signs" (pulso, texto, anel duplo, carrossel)
- [x] `hooks/taskbar-hero-update.js` — status por sessão, subagentes concorrentes
- [x] Nome real da aba do Warp via `warp.sqlite`
- [x] Repo público criado (`leonardosilvamelosantos/taskbar-code`)

### ✅ Checkpoint da Fase 1
- Resultado: `[x] aprovado` — testado ao vivo na máquina do autor, commit `ef8342e`

---

## Fase 2 — Simplificação + instalador (v1.1) ✅ concluída
**Meta:** código revisado (4 agentes: reuso/simplificação/eficiência/altitude) e instalação
possível em qualquer PC Windows, não só na máquina do autor.

- [x] Revisão de simplificação aplicada (commit `106e719`)
- [x] `install.ps1`/`uninstall.ps1` — detecção de Python/Node, merge de hooks idempotente,
      atalho de autostart sem `pywin32`
- [x] `INSTALL.md` escrito para um AGENTE seguir, não só um humano
- [x] Repo tornado público

### ✅ Checkpoint da Fase 2
- Resultado: `[x] aprovado` — commit `0b0de30`, testado contra `settings.json` real

---

## Fase 3 — Revisão de gaps + correções (v1.2) ✅ concluída
**Meta:** achar e corrigir lacunas reais de portabilidade/robustez/documentação/runtime
antes de considerar o projeto "pronto para qualquer máquina".

- [x] Revisão de gaps com 4 agentes em paralelo (portabilidade, robustez do instalador,
      documentação, runtime não testado)
- [x] BOM quebrando o hook silenciosamente — corrigido (confirmado por execução real)
- [x] `Read-Host` travando em sessão não-interativa — corrigido (confirmado por execução)
- [x] Race condition entre terminais (`status.json` compartilhado) — arquivo por sessão
- [x] Match de hook por caminho normalizado (não substring) — e a regressão que essa
      própria correção causou (duplicação por grafia de caminho diferente) também corrigida
- [x] DPI awareness, `time.monotonic()`, rotação de log, poda de cache, backup automático
      de `settings.json`, checagem de `bash`, `install.cmd`
- [x] Nova feature: `background{}` (tarefas `run_in_background`) — corrige o texto
      "Aguardando novo prompt" enganoso quando na verdade espera um comando em 2º plano

### ✅ Checkpoint da Fase 3
- Resultado: `[x] aprovado` — commit `6a084d4`, testado contra `settings.json` real
  (instalação do zero, idempotência, desinstalação, todas restauradas sem corrupção)

---

## Fase 4 — Candidatos para a próxima sessão (não iniciada)
**Meta:** a definir com o usuário — nenhum destes foi pedido explicitamente ainda, são
gaps de menor prioridade identificados na revisão da Fase 3 e deixados de propósito.

Achados de **altitude** (arquitetura mais profunda, ver `10-trd.md` e `90-decisions.md`):
- [ ] Campo de estado explícito no hook (`state: working|needs_you|idle`) em vez do ticker
      inferir por *string match* em `summary` (`derive_state()` em `ticker.pyw`)
- [ ] Mecanismo genérico de "name providers" em vez da cadeia hardcoded (Warp -> aiTitle ->
      derived -> cwd) em `collect_sessions()`
- [ ] Liveness genérico para agentes/background travados em `running` (hoje só TTL)

Outros gaps de menor prioridade (da revisão da Fase 3, não corrigidos):
- [ ] Barra de tarefas em monitor secundário (`Shell_SecondaryTrayWnd`) não considerada
- [ ] `_warp_name_cache` fica obsoleto para sempre se o Warp reiniciar (UUID muda)
- [ ] Sessões travadas/zumbis (`status busy` há horas sem `updatedAt` mudar) não são
      sinalizadas visualmente como possivelmente travadas

### ✅ Checkpoint da Fase 4
- Critério de aceite: a definir quando o usuário priorizar algum item acima
- Auditoria: subagente revisor confronta o entregue contra `10-trd.md`
- Code review: subagente revisor sobre o diff da fase
- Resultado: `[ ] pendente`

<!-- Teto: 250 linhas. -->
