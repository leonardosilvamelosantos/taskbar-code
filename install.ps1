#Requires -Version 5.1
<#
.SYNOPSIS
  Instala o Task Bar Hero: detecta Python/Node, registra os hooks no
  ~/.claude/settings.json (sem apagar hooks existentes), cria o atalho de
  inicializacao automatica e sobe o widget imediatamente.

.PARAMETER Yes
  Nao pergunta nada (assume "sim" para o patch opcional do /statusline).
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

$RepoRoot   = $PSScriptRoot
$HookPath   = Join-Path $RepoRoot 'hooks\taskbar-hero-update.js'
$TickerPath = Join-Path $RepoRoot 'ticker.pyw'
$ClaudeDir  = Join-Path $HOME '.claude'
$SettingsPath = Join-Path $ClaudeDir 'settings.json'

Write-Host "Task Bar Hero - instalador" -ForegroundColor Magenta
Write-Host "Repositorio: $RepoRoot`n"

# -- 1. Detectar Python (com tkinter) -----------------------------------------
Write-Step "Detectando Python 3 com Tkinter..."
$PythonwExe = $null

function Test-PythonCandidate ($exePath) {
    if (-not $exePath -or -not (Test-Path $exePath)) { return $false }
    & $exePath -c "import tkinter" 2>$null
    return ($LASTEXITCODE -eq 0)
}

try {
    $pyLauncherExe = (& py -3 -c "import sys; print(sys.executable)" 2>$null)
    if ($LASTEXITCODE -eq 0 -and $pyLauncherExe) {
        $pyLauncherExe = $pyLauncherExe.Trim()
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
    Write-Err "Python 3 com suporte a Tkinter nao encontrado."
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

# -- 3. Mesclar hooks em settings.json -----------------------------------------
Write-Step "Configurando hooks em $SettingsPath..."
New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null

if (Test-Path $SettingsPath) {
    $settings = Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    $settings = [PSCustomObject]@{}
}

if (-not $settings.PSObject.Properties['hooks']) {
    $settings | Add-Member -MemberType NoteProperty -Name 'hooks' -Value ([PSCustomObject]@{})
}

$hookCommand = "node `"$HookPath`""
$events = @('UserPromptSubmit', 'SessionStart', 'SessionEnd', 'PreToolUse', 'PostToolUse', 'Notification', 'Stop')
$added = @()

foreach ($evt in $events) {
    if (-not $settings.hooks.PSObject.Properties[$evt]) {
        $settings.hooks | Add-Member -MemberType NoteProperty -Name $evt -Value @()
    }
    $groups = @($settings.hooks.$evt)
    $alreadyThere = $false
    foreach ($g in $groups) {
        foreach ($h in @($g.hooks)) {
            if ($h.command -and $h.command -like '*taskbar-hero-update.js*') { $alreadyThere = $true }
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
                $answer = Read-Host "Encontrei seu /statusline em '$slPath'. Aplicar patch para alimentar o anel de uso (contexto/rate-limit)? [s/N]"
                $doPatch = $answer -match '^[sS]'
            }
            if ($doPatch) {
                $writeIdx = $slContent.LastIndexOf('process.stdout.write')
                if ($writeIdx -ge 0) {
                    Copy-Item $slPath "$slPath.bak" -Force
                    $patch = Get-Content (Join-Path $RepoRoot 'statusline-patch.snippet.js') -Raw -Encoding UTF8
                    $newContent = $slContent.Insert($writeIdx, $patch + "`n`n")
                    Set-Utf8NoBom -Path $slPath -Content $newContent
                    Write-Ok "/statusline atualizado (backup em $slPath.bak)"
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

# -- 5. Atalho de inicializacao automatica --------------------------------------
Write-Step "Criando atalho de inicializacao automatica..."
$Startup = [Environment]::GetFolderPath('Startup')
$ShortcutPath = Join-Path $Startup 'ClaudeTaskbarHero.lnk'
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = $PythonwExe
$Shortcut.Arguments = "`"$TickerPath`""
$Shortcut.WorkingDirectory = $RepoRoot
$Shortcut.WindowStyle = 7
$Shortcut.Save()
Write-Ok "Atalho criado em $ShortcutPath"

# -- 6. Subir o ticker agora -----------------------------------------------------
Write-Step "Iniciando o Task Bar Hero..."
Get-CimInstance Win32_Process -Filter "Name='pythonw.exe' or Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*ticker.pyw*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Process -FilePath $PythonwExe -ArgumentList "`"$TickerPath`"" -WorkingDirectory $RepoRoot
Start-Sleep -Seconds 1
Write-Ok "Task Bar Hero no ar."

Write-Host ""
Write-Host "Instalacao concluida." -ForegroundColor Green
Write-Host "Para desinstalar:  powershell -ExecutionPolicy Bypass -File uninstall.ps1"
