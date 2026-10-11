#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$DraftPath
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$originalOutputEncoding = $OutputEncoding
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$tempDir = $null
$exitCode = 1

try {
    if (-not (Test-Path -LiteralPath $DraftPath -PathType Leaf)) {
        throw "Draft file does not exist: $DraftPath"
    }
    $DraftPath = (Resolve-Path -LiteralPath $DraftPath).ProviderPath
    $vimPath = $env:CODEX_PROMPT_COACH_VIM
    if (-not $vimPath -or -not (Test-Path -LiteralPath $vimPath -PathType Leaf)) {
        throw 'Vim is not configured. Run enable.ps1 in this PowerShell session first.'
    }

    $draft = [System.IO.File]::ReadAllText($DraftPath, [System.Text.Encoding]::UTF8)
    $editorArgs = @('--clean', '-n', '--cmd', 'set encoding=utf-8 nomodeline',
        '-c', 'setlocal fileencoding=utf-8')
    $editorFiles = @($DraftPath)

    if (-not [string]::IsNullOrWhiteSpace($draft)) {
        try {
            $tempDir = Join-Path $tempRoot ('codex-coach-' + [guid]::NewGuid())
            [System.IO.Directory]::CreateDirectory($tempDir) | Out-Null
            $suggestionPath = Join-Path $tempDir 'suggestion.md'
            $logPath = Join-Path $tempDir 'codex.log'
            $promptPath = Join-Path $PSScriptRoot '..\prompts\coach-prompt.txt'
            $coachPrompt = [System.IO.File]::ReadAllText($promptPath, [System.Text.Encoding]::UTF8)
            $request = $coachPrompt + "`n`nDRAFT (JSON-encoded text):`n" +
                (ConvertTo-Json -InputObject $draft -Compress)
            $codexPath = (Get-Command codex -CommandType Application -ErrorAction Stop |
                Select-Object -First 1).Source
            $codexArgs = @('exec', '--model', 'gpt-6-luna',
                '-c', 'model_reasoning_effort="medium"',
                '-c', 'approval_policy="never"', '-c', 'web_search="disabled"',
                '--ignore-user-config', '--ephemeral', '--sandbox', 'read-only',
                '--disable', 'shell_tool', '--disable', 'plugins',
                '--disable', 'hooks', '--disable', 'apps', '--disable', 'multi_agent',
                '--disable', 'code_mode_host', '--skip-git-repo-check',
                '--color', 'never', '-C', $tempDir,
                '--output-last-message', $suggestionPath, '-')

            Write-Host 'Coaching your prompt with gpt-6-luna (medium)...'
            $request | & $codexPath @codexArgs > $logPath 2>&1
            if ($LASTEXITCODE -ne 0) {
                $detail = Get-Content -LiteralPath $logPath -Tail 3 -Encoding utf8
                throw "Codex exited with code $LASTEXITCODE. $($detail -join ' ')"
            }
            if (-not (Test-Path -LiteralPath $suggestionPath -PathType Leaf) -or
                [string]::IsNullOrWhiteSpace([System.IO.File]::ReadAllText($suggestionPath))) {
                throw 'Codex returned no suggestion.'
            }

            $editorArgs += @('-O', '-c',
                'wincmd l | setlocal readonly nomodifiable | wincmd h')
            $editorFiles += $suggestionPath
        }
        catch {
            Write-Warning "Correction unavailable: $($_.Exception.Message) Opening the original draft in Vim."
        }
    }

    & $vimPath @editorArgs -- @editorFiles
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Warning "Vim exited with code $exitCode. The coach has not overwritten your draft."
    }
}
catch {
    Write-Error $_ -ErrorAction Continue
}
finally {
    $OutputEncoding = $originalOutputEncoding
    if ($tempDir) {
        $cleanupPath = [System.IO.Path]::GetFullPath($tempDir)
        $allowedPrefix = $tempRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        if ($cleanupPath.StartsWith($allowedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $cleanupPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

exit $exitCode
