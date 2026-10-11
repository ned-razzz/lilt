#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$VimPath,
    [switch]$Disable,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$sessionState = Get-Variable -Name CodexPromptCoachSession -Scope Global -ErrorAction SilentlyContinue

if ($Disable) {
    if ($sessionState) {
        foreach ($name in $sessionState.Value.Keys) {
            if ($null -eq $sessionState.Value[$name]) {
                Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            }
            else {
                [System.Environment]::SetEnvironmentVariable($name, $sessionState.Value[$name], 'Process')
            }
        }
        Remove-Variable -Name CodexPromptCoachSession -Scope Global
    }
    if (-not $Quiet) { Write-Host 'Prompt coaching disabled in this PowerShell session.' }
    return
}

Get-Command pwsh, codex -CommandType Application -ErrorAction Stop | Out-Null
$wrapperPath = Join-Path $PSScriptRoot 'bin\codex-prompt-coach.cmd'
if (-not (Test-Path -LiteralPath $wrapperPath -PathType Leaf)) {
    throw "Coach wrapper is missing: $wrapperPath"
}

$gitPath = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
if ($VimPath) {
    if (-not (Test-Path -LiteralPath $VimPath -PathType Leaf)) {
        throw "Vim executable does not exist: $VimPath"
    }
}
else {
    $vimCommand = Get-Command vim -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $candidates = @($env:CODEX_PROMPT_COACH_VIM, $vimCommand.Source,
        ([string]$env:EDITOR).Trim('"'), ([string]$env:VISUAL).Trim('"'),
        (Join-Path (Split-Path $gitPath -Parent) '..\usr\bin\vim.exe'))
    $VimPath = $candidates | Where-Object {
        $_ -and ([System.IO.Path]::GetFileName($_) -eq 'vim.exe') -and
        (Test-Path -LiteralPath $_ -PathType Leaf)
    } | Select-Object -First 1
    if (-not $VimPath) {
        throw 'Vim was not found. Run enable.ps1 -VimPath "C:\path\vim.exe".'
    }
}
$VimPath = (Resolve-Path -LiteralPath $VimPath).ProviderPath

$gitEditor = $env:GIT_EDITOR
if ([string]::IsNullOrEmpty($gitEditor)) {
    $gitEditor = & $gitPath var GIT_EDITOR
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitEditor)) {
        throw 'Cannot determine the existing Git editor. Set GIT_EDITOR before enabling the coach.'
    }
}

if (-not $sessionState) {
    $global:CodexPromptCoachSession = @{}
    foreach ($name in @('VISUAL', 'GIT_EDITOR', 'CODEX_PROMPT_COACH_VIM')) {
        $global:CodexPromptCoachSession[$name] =
            [System.Environment]::GetEnvironmentVariable($name, 'Process')
    }
}
$env:GIT_EDITOR = $gitEditor
$env:CODEX_PROMPT_COACH_VIM = $VimPath
$env:VISUAL = '"' + $wrapperPath + '"'
if (-not $Quiet) { Write-Host 'Prompt coaching enabled in this PowerShell session. Run codex, then press Ctrl+G.' }
