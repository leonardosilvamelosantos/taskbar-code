> 🇺🇸 [Read in English](CONTRIBUTING.md)

# Contribuindo com o Task Bar Hero

Obrigado por considerar contribuir. Este projeto tem algumas convenções não
óbvias que já causaram quebras reais no passado — leia isto antes de abrir
um PR.

## Setup de desenvolvimento

- Rode `python ticker.pyw` (em vez de clicar duas vezes no `.pyw`) para ter
  console e ver exceções.
- Rode o lint do hook com `node -c hooks/taskbar-hero-update.js` antes de
  commitar.
- Não há suite de testes automatizada. Validação manual e funcional é o
  padrão para toda mudança — veja "Testando mudanças no instalador" abaixo.

## Convenções de encoding (leia antes de tocar em `.ps1` ou JSON)

Essas duas regras já causaram quebras reais neste projeto — não são
preferência de estilo:

- **Arquivos `.ps1` precisam ser ASCII-only.** Um acento ou um em-dash num
  `.ps1` sem BOM quebra o parser do PowerShell 5.1 de forma direta (erro de
  sintaxe, não um aviso). Se precisar comunicar algo não-ASCII na saída de
  um script, use pontuação ASCII simples em vez disso.
- **Todo JSON escrito pelo projeto precisa ser UTF-8 sem BOM.** O próprio
  parser de `settings.json` do Claude Code não tolera BOM. No PowerShell
  5.1, `Set-Content -Encoding UTF8` adiciona BOM por padrão — use
  `[System.IO.File]::WriteAllText($path, $json, (New-Object
  System.Text.UTF8Encoding($false)))` em vez disso.

## Testando mudanças em `install.ps1` / `uninstall.ps1`

Não há CI nem um `settings.json` de sandbox — mudanças no instalador
precisam ser testadas contra um `~/.claude/settings.json` real. O ciclo
obrigatório:

1. **Faça backup** de `~/.claude/settings.json` antes de rodar qualquer
   coisa.
2. Rode o script (`install.ps1` ou `uninstall.ps1`) contra esse arquivo
   real.
3. Verifique o resultado: o JSON continua válido, os hooks esperados foram
   adicionados/removidos, nenhum hook que o usuário já tinha para outras
   finalidades foi tocado, e o arquivo não tem BOM.
4. **Restaure** o backup quando terminar de testar, a menos que você
   realmente queira manter a mudança instalada.

Teste tanto uma instalação do zero (sem hooks do Task Bar Hero
preexistentes) quanto rodar de novo numa instalação já feita (idempotência
— rodar duas vezes não pode duplicar hooks).

## Zero dependências é uma restrição de design, não um acidente

O widget (`ticker.pyw`) usa só a stdlib do Python, e o hook
(`hooks/taskbar-hero-update.js`) usa só a stdlib do Node. PRs que
adicionarem uma dependência de `pip install` ou `npm install` serão
recusados por padrão. Se você acha que uma dependência é realmente
inevitável, abra uma issue para discutir antes de escrever o código.

## Fluxo de Pull Request

1. Faça fork do repositório.
2. Crie uma branch para sua mudança.
3. Abra um PR contra `master`. Mantenha um assunto por PR — não misture
   correções não relacionadas.
4. Escreva mensagens de commit no imperativo ("Fix X", não "Fixed X" ou
   "Fixes X").
5. Descreva na descrição do PR como você testou a mudança manualmente (veja
   acima) — não há CI para se apoiar.
