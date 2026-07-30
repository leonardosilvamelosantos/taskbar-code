> 🇧🇷 [Leia em português](CONTRIBUTING.pt-BR.md)

# Contributing to Task Bar Hero

Thanks for considering a contribution. This project has a few non-obvious
conventions that have already broken things in the past — please read this
before opening a PR.

## Development setup

- Run `python ticker.pyw` (not double-clicking the `.pyw` file) so you get a
  console and can see exceptions.
- Lint the hook with `node -c hooks/taskbar-hero-update.js` before
  committing.
- There is no automated test suite. Manual, functional verification is the
  standard for every change — see "Testing installer changes" below.

## Encoding conventions (read this before touching `.ps1` or JSON)

These two rules have caused real breakage in this project before — they're
not stylistic preferences:

- **`.ps1` files must be ASCII-only.** An accented character or an em-dash
  in a `.ps1` file without a BOM breaks the PowerShell 5.1 parser outright
  (syntax error, not a warning). If you need to communicate something
  non-ASCII in a script's output, use plain ASCII punctuation instead.
- **Any JSON the project writes must be UTF-8 without BOM.** Claude Code's
  own `settings.json` parser does not tolerate a BOM. In PowerShell 5.1,
  `Set-Content -Encoding UTF8` adds a BOM by default — use
  `[System.IO.File]::WriteAllText($path, $json, (New-Object
  System.Text.UTF8Encoding($false)))` instead.

## Testing changes to `install.ps1` / `uninstall.ps1`

There's no CI and no sandbox `settings.json` — changes to the installer must
be tested against a real `~/.claude/settings.json`. The required cycle:

1. **Back up** `~/.claude/settings.json` before running anything.
2. Run the script (`install.ps1` or `uninstall.ps1`) against that real file.
3. Verify the result: the JSON is still valid, the expected hooks were
   added/removed, no existing hooks the user had for other purposes were
   touched, and the file has no BOM.
4. **Restore** the backup once you're done testing, unless you actually
   intend to keep the change installed.

Test both a fresh install (no prior Task Bar Hero hooks) and a re-run on an
already-installed setup (idempotency — running twice must not duplicate
hooks).

## Zero dependencies is a design constraint, not an accident

The widget (`ticker.pyw`) uses only Python's stdlib, and the hook
(`hooks/taskbar-hero-update.js`) uses only Node's stdlib. PRs that add a
`pip install` or `npm install` requirement will be declined by default. If
you believe a dependency is genuinely unavoidable, open an issue to discuss
it before writing the code.

## Pull request flow

1. Fork the repository.
2. Create a branch for your change.
3. Open a PR against `master`. Keep one subject per PR — don't bundle
   unrelated fixes.
4. Write commit messages in the imperative ("Fix X", not "Fixed X" or
   "Fixes X").
5. Describe how you tested the change manually (see above) in the PR
   description — there's no CI to fall back on.
