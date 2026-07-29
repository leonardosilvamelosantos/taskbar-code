#Requires -Version 5.1
<#
.SYNOPSIS
  Desinstala o Task Bar Hero: encerra o processo, remove o atalho de
  inicializacao, remove so os hooks que apontam para ESTE clone do repo
  (preservando qualquer outro hook do usuario, inclusive de outro clone) e
  opcionalmente apaga o estado salvo.

.PARAMETER Yes
  Nao pergunta nada (assume "sim" para apagar o estado salvo tambem).
#>
param(
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

function Write-Step ($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok   ($msg) { Write-Host "OK  $msg" -ForegroundColor Green }
function Write-Warn ($msg) { Write-Host "!!  $msg" -ForegroundColor Yellow }

# Mesmo motivo do install.ps1: Set-Content -Encoding UTF8 grava BOM, que
# quebra parsers de JSON que nao esperam BOM (inclusive o proprio Claude Code).
function Set-Utf8NoBom ($Path, $Content) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

# Mesmo motivo do install.ps1: Read-Host lanca excecao terminante em sessao
# nao-interativa - nunca deixar isso abortar o script no meio.
function Read-HostSafe ($Prompt) {
    try {
        return Read-Host $Prompt
    } catch {
        Write-Warn "Console nao-interativo - nao foi possivel perguntar. Assumindo 'nao'."
        return $null
    }
}

$RepoRoot     = $PSScriptRoot
$HookPathFile = Join-Path $RepoRoot 'hooks\taskbar-hero-update.js'
$HookPath     = if (Test-Path $HookPathFile) { (Resolve-Path $HookPathFile).Path } else { $HookPathFile }
$ClaudeDir    = Join-Path $HOME '.claude'
$SettingsPath = Join-Path $ClaudeDir 'settings.json'
$StateDir     = Join-Path $ClaudeDir 'taskbar-hero'

Write-Host "Task Bar Hero - desinstalador" -ForegroundColor Magenta

Write-Step "Encerrando o processo do ticker..."
try {
    Get-CimInstance Win32_Process -Filter "Name='pythonw.exe' or Name='python.exe'" -ErrorAction Stop |
        Where-Object { $_.CommandLine -like '*ticker.pyw*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Write-Ok "Processo encerrado (se estava rodando)."
} catch {
    Write-Warn "Nao consegui consultar processos via WMI (pode estar bloqueado por politica) - encerre manualmente pelo Gerenciador de Tarefas se necessario."
}

Write-Step "Removendo atalho de inicializacao..."
$ShortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'ClaudeTaskbarHero.lnk'
Remove-Item -Path $ShortcutPath -ErrorAction SilentlyContinue
Write-Ok "Atalho removido (se existia)."

if (Test-Path $SettingsPath) {
    Write-Step "Removendo hooks do Task Bar Hero em settings.json..."
    try {
        $settings = Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Warn "settings.json contem JSON invalido - pulando remocao de hooks (nada foi alterado nele). Corrija manualmente."
        $settings = $null
    }

    if ($settings) {
        $changed = $false
        # Casa pelo CAMINHO ABSOLUTO deste clone (normalizado), nao por um
        # substring solto do nome do arquivo - assim nao apaga hooks de OUTRO
        # clone do mesmo repo instalado em outra pasta. A normalizacao cobre
        # tambem entradas gravadas com grafia diferente (barras, "$HOME").
        function Get-HookCommandPath ($command) {
            if ($command -match '"([^"]+)"') {
                $p = $matches[1] -replace '\$HOME', $HOME
                return ($p -replace '/', '\').TrimEnd('\')
            }
            return $null
        }
        $hookPathNormalized = $HookPath.TrimEnd('\')
        if ($settings.PSObject.Properties['hooks']) {
            foreach ($evt in $settings.hooks.PSObject.Properties.Name) {
                $before = @($settings.hooks.$evt)
                # @(...) forca array mesmo quando o resultado fica vazio -- sem
                # isso o PowerShell colapsa pipeline vazio para $null, que vira
                # "null" no JSON em vez de "[]".
                $after = @($before | Where-Object {
                    $group = $_
                    -not (@($group.hooks) | Where-Object { $_.command -and (Get-HookCommandPath $_.command) -ieq $hookPathNormalized })
                })
                if ($after.Count -ne $before.Count) { $changed = $true }
                $settings.hooks.$evt = $after
            }
        }
        if ($changed) {
            Copy-Item $SettingsPath "$SettingsPath.bak" -Force
            Set-Utf8NoBom -Path $SettingsPath -Content ($settings | ConvertTo-Json -Depth 30)
            Write-Ok "Hooks removidos - outros hooks seus (inclusive de outros clones deste repo) foram preservados."
        } else {
            Write-Ok "Nenhum hook deste clone encontrado (nada a remover)."
        }
    }
}

$removeState = $Yes
if (-not $Yes -and (Test-Path $StateDir)) {
    $answer = Read-HostSafe "Apagar tambem o estado salvo em $StateDir (posicao da janela, status)? [s/N]"
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
