#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$VimPath,
    [switch]$Disable,
    [switch]$Quiet
)

# Configuration shared by Main and the Vim resolver, scoped to this script.
$script:coachWrapperPath = Join-Path $PSScriptRoot 'bin\lilt.cmd'
$script:editorEnvironmentNames = @('VISUAL', 'GIT_EDITOR', 'LILT_VIM')

function Resolve-VimPath([string]$requestedPath, [string]$gitExecutablePath) {
    if ($requestedPath) {
        if (-not (Test-Path -LiteralPath $requestedPath -PathType Leaf)) {
            throw "Vim executable does not exist: $requestedPath"
        }
        return (Resolve-Path -LiteralPath $requestedPath).ProviderPath
    }

    # Prefer the configured Vim, then PATH/editor settings, then Git's bundled Vim.
    $vimOnPath = Get-Command vim -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $gitDirectory = Split-Path $gitExecutablePath -Parent
    $bundledVimPath = Join-Path $gitDirectory '..\usr\bin\vim.exe'
    $candidatePaths = @(
        $env:LILT_VIM
        $vimOnPath.Source
        ([string]$env:EDITOR).Trim('"')
        ([string]$env:VISUAL).Trim('"')
        $bundledVimPath
    )
    $resolvedVimPath = $candidatePaths | Where-Object {
        $_ -and ([System.IO.Path]::GetFileName($_) -eq 'vim.exe') -and
        (Test-Path -LiteralPath $_ -PathType Leaf)
    } | Select-Object -First 1
    if (-not $resolvedVimPath) {
        throw 'Vim was not found. Run enable.ps1 -VimPath "C:\path\vim.exe".'
    }
    return (Resolve-Path -LiteralPath $resolvedVimPath).ProviderPath
}

function Main {
    $ErrorActionPreference = 'Stop'
    $PSNativeCommandUseErrorActionPreference = $false
    $sessionState = Get-Variable LiltSession -Scope Global -ErrorAction SilentlyContinue

    # Disable needs no external programs: restore the snapshot from the first activation.
    if ($Disable) {
        if ($sessionState) {
            foreach ($name in $sessionState.Value.Keys) {
                $originalValue = $sessionState.Value[$name]
                if ($null -eq $originalValue) {
                    Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
                }
                else {
                    [System.Environment]::SetEnvironmentVariable($name, $originalValue, 'Process')
                }
            }
            Remove-Variable LiltSession -Scope Global
        }
        if (-not $Quiet) { Write-Host 'Prompt coaching disabled in this PowerShell session.' }
        return
    }

    # Resolve dependencies before changing any environment variables.
    Get-Command pwsh, codex -CommandType Application -ErrorAction Stop | Out-Null
    if (-not (Test-Path -LiteralPath $script:coachWrapperPath -PathType Leaf)) {
        throw "Coach wrapper is missing: $script:coachWrapperPath"
    }
    $gitApplication = Get-Command git -CommandType Application -ErrorAction Stop |
        Select-Object -First 1
    $resolvedVimPath = Resolve-VimPath -requestedPath $VimPath -gitExecutablePath $gitApplication.Source

    # Ask Git for its current editor before setting VISUAL, which Git may otherwise inherit.
    $gitEditor = $env:GIT_EDITOR
    if ([string]::IsNullOrEmpty($gitEditor)) {
        $gitEditor = & $gitApplication.Source var GIT_EDITOR
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitEditor)) {
            throw 'Cannot determine the existing Git editor. Set GIT_EDITOR before enabling the coach.'
        }
    }

    # This snapshot must outlive this script so a later -Disable call can restore it.
    # Repeated activation preserves the first snapshot instead of replacing it.
    if (-not $sessionState) {
        $global:LiltSession = @{}
        foreach ($name in $script:editorEnvironmentNames) {
            $global:LiltSession[$name] =
                [System.Environment]::GetEnvironmentVariable($name, 'Process')
        }
    }
    $env:GIT_EDITOR = $gitEditor
    $env:LILT_VIM = $resolvedVimPath
    $env:VISUAL = '"' + $script:coachWrapperPath + '"'
    if (-not $Quiet) {
        Write-Host 'Prompt coaching enabled in this PowerShell session. Run codex, then press Ctrl+G.'
    }
}

# Entry point.
Main
