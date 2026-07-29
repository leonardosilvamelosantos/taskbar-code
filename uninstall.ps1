#Requires -Version 5.1
<#
.SYNOPSIS
  Desinstala o Task Bar Hero: encerra o processo, remove o atalho de
  inicializacao, remove so os hooks que sao nossos do settings.json
  (preservando qualquer outro hook do usuario) e opcionalmente apaga o
  estado salvo.

.PARAMETER Yes
  Nao pergunta nada (assume "sim" para apagar o estado salvo tambem).
#>
param(
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

function Write-Step ($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok   ($msg) { Write-Host "OK  $msg" -ForegroundColor Green }

# Mesmo motivo do install.ps1: Set-Content -Encoding UTF8 grava BOM, que
# quebra parsers de JSON que nao esperam BOM (inclusive o proprio Claude Code).
function Set-Utf8NoBom ($Path, $Content) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

$ClaudeDir    = Join-Path $HOME '.claude'
$SettingsPath = Join-Path $ClaudeDir 'settings.json'
$StateDir     = Join-Path $ClaudeDir 'taskbar-hero'

Write-Host "Task Bar Hero - desinstalador" -ForegroundColor Magenta

Write-Step "Encerrando o processo do ticker..."
Get-CimInstance Win32_Process -Filter "Name='pythonw.exe' or Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*ticker.pyw*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Write-Ok "Processo encerrado (se estava rodando)."

Write-Step "Removendo atalho de inicializacao..."
$ShortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'ClaudeTaskbarHero.lnk'
Remove-Item -Path $ShortcutPath -ErrorAction SilentlyContinue
Write-Ok "Atalho removido (se existia)."

if (Test-Path $SettingsPath) {
    Write-Step "Removendo hooks do Task Bar Hero em settings.json..."
    $settings = Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $changed = $false
    if ($settings.PSObject.Properties['hooks']) {
        foreach ($evt in $settings.hooks.PSObject.Properties.Name) {
            $before = @($settings.hooks.$evt)
            # @(...) forca array mesmo quando o resultado fica vazio -- sem
            # isso o PowerShell colapsa pipeline vazio para $null, que vira
            # "null" no JSON em vez de "[]".
            $after = @($before | Where-Object {
                $group = $_
                -not (@($group.hooks) | Where-Object { $_.command -like '*taskbar-hero-update.js*' })
            })
            if ($after.Count -ne $before.Count) { $changed = $true }
            $settings.hooks.$evt = $after
        }
    }
    if ($changed) {
        Set-Utf8NoBom -Path $SettingsPath -Content ($settings | ConvertTo-Json -Depth 30)
        Write-Ok "Hooks removidos - outros hooks seus foram preservados."
    } else {
        Write-Ok "Nenhum hook do Task Bar Hero encontrado (nada a remover)."
    }
}

$removeState = $Yes
if (-not $Yes -and (Test-Path $StateDir)) {
    $answer = Read-Host "Apagar tambem o estado salvo em $StateDir (posicao da janela, status)? [s/N]"
    $removeState = $answer -match '^[sS]'
}
if ($removeState -and (Test-Path $StateDir)) {
    Remove-Item -Recurse -Force -Path $StateDir -ErrorAction SilentlyContinue
    Write-Ok "Estado removido."
} elseif (Test-Path $StateDir) {
    Write-Host "Estado mantido em $StateDir." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Desinstalacao concluida." -ForegroundColor Green
Write-Host "Nota: o patch do /statusline (se voce aceitou aplica-lo) nao e revertido automaticamente - restaure o .bak criado ao lado do arquivo, se quiser."
