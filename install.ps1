#Requires -Version 5.1
<#
.SYNOPSIS
  Instala o Task Bar Hero: detecta Python/Node, registra os hooks no
  ~/.claude/settings.json (sem apagar hooks existentes), cria o atalho de
  inicializacao automatica e sobe o widget imediatamente.

.PARAMETER Yes
  Nao pergunta nada (assume "sim" para o patch opcional do /statusline).
  Recomendado ao rodar de forma nao-interativa/autonoma (ex: por um agente) -
  sem isso, se o console nao aceitar input, o script pula o prompt sozinho
  e avisa, mas -Yes evita a checagem toda.
#>
param(
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

function Write-Step ($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Warn ($msg) { Write-Host "!!  $msg" -ForegroundColor Yellow }
function Write-Ok   ($msg) { Write-Host "OK  $msg" -ForegroundColor Green }
function Write-Err  ($msg) { Write-Host "ERRO  $msg" -ForegroundColor Red }

# Set-Content -Encoding UTF8 do PowerShell 5.1 grava BOM, o que quebra
# parsers de JSON que nao esperam BOM (inclusive o proprio Claude Code).
# Escreve sempre UTF-8 sem BOM via .NET direto.
function Set-Utf8NoBom ($Path, $Content) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

# Read-Host lanca excecao terminante em sessao nao-interativa (ex: rodado por
# um agente/ferramenta automatizada sem console real) - com
# $ErrorActionPreference='Stop' isso abortaria o script no meio da instalacao
# (hooks ja registrados, mas atalho/ticker nunca chegam a rodar). Em vez de
# travar ou crashar, trata como "nao" e avisa.
function Read-HostSafe ($Prompt) {
    try {
        return Read-Host $Prompt
    } catch {
        Write-Warn "Console nao-interativo - nao foi possivel perguntar. Assumindo 'nao'."
        return $null
    }
}

$RepoRoot   = $PSScriptRoot
$HookPath   = (Resolve-Path (Join-Path $RepoRoot 'hooks\taskbar-hero-update.js')).Path
$TickerPath = Join-Path $RepoRoot 'ticker.pyw'
$ClaudeDir  = Join-Path $HOME '.claude'
$SettingsPath = Join-Path $ClaudeDir 'settings.json'

Write-Host "Task Bar Hero - instalador" -ForegroundColor Magenta
Write-Host "Repositorio: $RepoRoot`n"

# Se o repo foi baixado como ZIP do GitHub (nao "git clone"), os arquivos
# ganham "Mark of the Web" e o SmartScreen/politica de execucao pode
# bloquear silenciosamente. Unblock-File e inofensivo mesmo sem MOTW.
Get-ChildItem -Path $RepoRoot -Recurse -File -ErrorAction SilentlyContinue |
    ForEach-Object { Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue }

# -- 1. Detectar Python (com tkinter) -----------------------------------------
Write-Step "Detectando Python 3 com Tkinter..."
$PythonwExe = $null

function Test-PythonCandidate ($exePath) {
    if (-not $exePath -or -not (Test-Path $exePath)) { return $false }
    & $exePath -c "import tkinter" 2>$null
    return ($LASTEXITCODE -eq 0)
}

try {
    $pyLauncherOut = @(& py -3 -c "import sys; print(sys.executable)" 2>$null)
    if ($LASTEXITCODE -eq 0 -and $pyLauncherOut.Count -gt 0) {
        # @() + Select-Object -Last 1 forca string unica mesmo se o launcher
        # emitir linhas extras em stdout (avisos de alguma distribuicao, etc.)
        $pyLauncherExe = ($pyLauncherOut | Select-Object -Last 1).ToString().Trim()
        if (Test-PythonCandidate $pyLauncherExe) {
            $PythonwExe = $pyLauncherExe -replace 'python\.exe$', 'pythonw.exe'
        }
    }
} catch {}

if (-not $PythonwExe) {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd -and (Test-PythonCandidate $cmd.Source)) {
        $PythonwExe = $cmd.Source -replace 'python\.exe$', 'pythonw.exe'
    }
}

if (-not $PythonwExe -or -not (Test-Path $PythonwExe)) {
    Write-Err "Python 3 com suporte a Tkinter nao encontrado (ou so o stub da Microsoft Store esta presente)."
    Write-Host "Instale com:  winget install -e --id Python.Python.3.12"
    Write-Host "Depois rode este instalador de novo."
    exit 1
}
Write-Ok "Python: $PythonwExe"

# -- 2. Detectar Node.js -------------------------------------------------------
Write-Step "Detectando Node.js..."
$NodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $NodeCmd) {
    Write-Err "Node.js nao encontrado."
    Write-Host "Instale com:  winget install -e --id OpenJS.NodeJS.LTS"
    Write-Host "Depois rode este instalador de novo."
    exit 1
}
Write-Ok "Node: $($NodeCmd.Source)"

# -- 2b. Detectar bash (usado no "shell" dos hooks registrados abaixo) --------
Write-Step "Detectando bash (necessario para os hooks rodarem)..."
$BashCmd = Get-Command bash -ErrorAction SilentlyContinue
if (-not $BashCmd) {
    Write-Warn "bash nao encontrado no PATH - os hooks registrados usam ""shell"": ""bash"" e vao falhar silenciosamente sem ele."
    Write-Warn "Instale com:  winget install -e --id Git.Git   (traz o Git Bash)"
} else {
    Write-Ok "bash: $($BashCmd.Source)"
}

# -- 3. Mesclar hooks em settings.json -----------------------------------------
Write-Step "Configurando hooks em $SettingsPath..."
New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null

if (Test-Path $SettingsPath) {
    try {
        $settings = Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Err "settings.json em '$SettingsPath' contem JSON invalido:"
        Write-Host "  $($_.Exception.Message)"
        Write-Err "Corrija o arquivo manualmente (ou restaure um backup) antes de rodar o instalador de novo. Nada foi alterado."
        exit 1
    }
    # Backup antes de qualquer reescrita do arquivo de configuracao central do
    # usuario - nunca sobrescrever sem uma copia de recuperacao possivel.
    Copy-Item $SettingsPath "$SettingsPath.bak" -Force
} else {
    $settings = [PSCustomObject]@{}
}

if (-not $settings.PSObject.Properties['hooks']) {
    $settings | Add-Member -MemberType NoteProperty -Name 'hooks' -Value ([PSCustomObject]@{})
}

$hookCommand = "node `"$HookPath`""
$events = @('UserPromptSubmit', 'SessionStart', 'SessionEnd', 'PreToolUse', 'PostToolUse', 'Notification', 'Stop', 'SubagentStop')
$added = @()

# Casa pelo CAMINHO ABSOLUTO do hook (normalizado), nao por um substring
# solto do nome do arquivo - com substring solto, dois clones deste repo em
# pastas diferentes se confundiriam: instalar o segundo clone acharia "ja
# esta instalado" (por causa do hook do primeiro) e nunca adicionaria o
# proprio; desinstalar um apagaria o hook do outro. A normalizacao (barras,
# "$HOME" expandido) evita o problema oposto: nao duplicar quando o mesmo
# caminho ja foi registrado com uma grafia diferente (ex: por uma versao
# anterior deste instalador que usava "$HOME/..." em vez do caminho
# resolvido).
function Get-HookCommandPath ($command) {
    if ($command -match '"([^"]+)"') {
        $p = $matches[1] -replace '\$HOME', $HOME
        return ($p -replace '/', '\').TrimEnd('\')
    }
    return $null
}
$hookPathNormalized = $HookPath.TrimEnd('\')

foreach ($evt in $events) {
    if (-not $settings.hooks.PSObject.Properties[$evt]) {
        $settings.hooks | Add-Member -MemberType NoteProperty -Name $evt -Value @()
    }
    $groups = @($settings.hooks.$evt)
    $alreadyThere = $false
    foreach ($g in $groups) {
        foreach ($h in @($g.hooks)) {
            if ($h.command -and (Get-HookCommandPath $h.command) -ieq $hookPathNormalized) { $alreadyThere = $true }
        }
    }
    if (-not $alreadyThere) {
        $newGroup = [PSCustomObject]@{
            hooks = @([PSCustomObject]@{ type = 'command'; command = $hookCommand; shell = 'bash' })
        }
        $groups = $groups + $newGroup
        $settings.hooks.$evt = $groups
        $added += $evt
    }
}

if ($added.Count -gt 0) {
    Set-Utf8NoBom -Path $SettingsPath -Content ($settings | ConvertTo-Json -Depth 30)
    Write-Ok ("Hooks adicionados para: " + ($added -join ', '))
} else {
    Write-Ok "Hooks ja estavam configurados - nada a fazer (settings.json nao foi reescrito)."
}

# -- 4. Patch opcional do /statusline -------------------------------------------
Write-Step "Verificando /statusline customizado..."
if ($settings.PSObject.Properties['statusLine'] -and $settings.statusLine.command) {
    $slMatch = [regex]::Match($settings.statusLine.command, '"([^"]+\.js)"')
    if ($slMatch.Success -and (Test-Path $slMatch.Groups[1].Value)) {
        $slPath = $slMatch.Groups[1].Value
        $slContent = Get-Content $slPath -Raw -Encoding UTF8
        if ($slContent -match 'Task Bar Hero') {
            Write-Ok "/statusline ja tem o patch do Task Bar Hero."
        } elseif ($slContent -notmatch '\bdata\b' -or $slContent -notmatch '\busedPct\b' -or $slContent -notmatch '\bsessionLimit\b') {
            Write-Warn "Seu /statusline nao usa as variaveis esperadas (data/usedPct/sessionLimit)."
            Write-Warn "Pulando o patch automatico - aplique manualmente (veja statusline-patch.md). O anel de uso (5h) fica vazio ate la."
        } else {
            $doPatch = $Yes
            if (-not $Yes) {
                $answer = Read-HostSafe "Encontrei seu /statusline em '$slPath'. Aplicar patch para alimentar o anel de uso (contexto/rate-limit)? [s/N]"
                $doPatch = $answer -match '^[sS]'
            }
            if ($doPatch) {
                $writeIdx = $slContent.LastIndexOf('process.stdout.write')
                if ($writeIdx -ge 0) {
                    Copy-Item $slPath "$slPath.bak" -Force
                    $patch = Get-Content (Join-Path $RepoRoot 'statusline-patch.snippet.js') -Raw -Encoding UTF8
                    $newContent = $slContent.Insert($writeIdx, $patch + "`n`n")
                    Set-Utf8NoBom -Path $slPath -Content $newContent
                    $syntaxCheck = & node --check $slPath 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Copy-Item "$slPath.bak" $slPath -Force
                        Write-Err "O patch quebrou a sintaxe do /statusline - revertido para o original. Detalhe: $syntaxCheck"
                        Write-Warn "Aplique manualmente (veja statusline-patch.md), com mais cuidado no ponto de insercao."
                    } else {
                        Write-Ok "/statusline atualizado e validado (backup em $slPath.bak)"
                    }
                } else {
                    Write-Warn "Nao achei onde inserir o patch automaticamente - aplique manualmente (statusline-patch.md)."
                }
            } else {
                Write-Warn "Pulado - o anel de uso (5h) fica vazio ate isso ser aplicado manualmente (veja statusline-patch.md)."
            }
        }
    }
} else {
    Write-Warn "Nenhum /statusline customizado encontrado - o anel de uso (5h) fica vazio (ok, o resto funciona normalmente)."
}

# -- 5. Atalhos (autostart, Menu Iniciar, Area de Trabalho) ---------------------
Write-Step "Criando atalhos..."
$WshShell = New-Object -ComObject WScript.Shell

function New-TbhShortcut ($Path) {
    $Shortcut = $WshShell.CreateShortcut($Path)
    $Shortcut.TargetPath = $PythonwExe
    $Shortcut.Arguments = "`"$TickerPath`""
    $Shortcut.WorkingDirectory = $RepoRoot
    $Shortcut.WindowStyle = 7
    $Shortcut.Save()
    Write-Ok "Atalho criado em $Path"
}

# Nome do atalho de autostart nao muda: uninstall.ps1 e INSTALL.md ja
# referenciam esse nome exato.
$StartupShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'ClaudeTaskbarHero.lnk'
New-TbhShortcut -Path $StartupShortcut

# Menu Iniciar e Area de Trabalho: nome legivel (e o texto que aparece na
# busca do Menu Iniciar), para o usuario conseguir reabrir o widget depois
# de fechar sem precisar relogar ou rodar o instalador de novo.
$StartMenuShortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Task Bar Hero Code.lnk'
New-TbhShortcut -Path $StartMenuShortcut

$DesktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Task Bar Hero Code.lnk'
New-TbhShortcut -Path $DesktopShortcut

# -- 5b. Comando /taskbar-hero global no Claude Code -----------------------------
Write-Step "Instalando comando /taskbar-hero..."
$CommandTemplatePath = Join-Path $RepoRoot 'commands\taskbar-hero.md.template'
$CommandsDir = Join-Path $ClaudeDir 'commands'
if (-not (Test-Path $CommandsDir)) {
    New-Item -ItemType Directory -Path $CommandsDir -Force | Out-Null
}
$CommandContent = (Get-Content $CommandTemplatePath -Raw -Encoding UTF8) -replace '\{\{REPO_ROOT\}\}', $RepoRoot
$CommandDestPath = Join-Path $CommandsDir 'taskbar-hero.md'
Set-Utf8NoBom -Path $CommandDestPath -Content $CommandContent
Write-Ok "Comando /taskbar-hero instalado em $CommandDestPath"

# -- 6. Subir o ticker agora -----------------------------------------------------
Write-Step "Iniciando o Task Bar Hero..."
try {
    Get-CimInstance Win32_Process -Filter "Name='pythonw.exe' or Name='python.exe'" -ErrorAction Stop |
        Where-Object { $_.CommandLine -like '*ticker.pyw*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} catch {
    Write-Warn "Nao consegui consultar processos via WMI (pode estar bloqueado por politica) - se ja havia uma instancia rodando, ela pode continuar ativa junto com a nova."
}

$proc = Start-Process -FilePath $PythonwExe -ArgumentList "`"$TickerPath`"" -WorkingDirectory $RepoRoot -PassThru
Start-Sleep -Seconds 1
$stillRunning = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if ($stillRunning) {
    Write-Ok "Task Bar Hero no ar (PID $($proc.Id))."
} else {
    Write-Err "O processo encerrou logo apos iniciar (isso acontece em sessoes sem estacao de janela interativa, ex: RDP/SSH headless)."
    $logPath = Join-Path $ClaudeDir 'taskbar-hero\ticker.log'
    if (Test-Path $logPath) {
        Write-Host "Ultimas linhas de ${logPath}:"
        Get-Content $logPath -Tail 20
    } else {
        Write-Warn "Nenhum log em $logPath - a falha aconteceu antes do widget conseguir logar (provavelmente falta de estacao de janela)."
    }
}

Write-Host ""
Write-Host "Instalacao concluida." -ForegroundColor Green
Write-Host "Para desinstalar:  powershell -ExecutionPolicy Bypass -File uninstall.ps1"
