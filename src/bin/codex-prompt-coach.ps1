#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$DraftPath
)

# Script-wide configuration keeps the invocation details out of Main's execution flow.
$script:utf8Encoding = [System.Text.UTF8Encoding]::new($false)
$script:coachPromptPath = Join-Path $PSScriptRoot '..\prompts\coach-prompt.txt'
$script:baseEditorArguments = @(
    '--clean', '-n', '--cmd', 'set encoding=utf-8 nomodeline'
    '-c', 'setlocal fileencoding=utf-8'
)
$script:suggestionPaneCommand = 'wincmd l | setlocal readonly nomodifiable | wincmd h'
$script:baseCodexArguments = @(
    'exec', '--model', 'gpt-6-luna'
    '-c', 'model_reasoning_effort="medium"'
    '-c', 'approval_policy="never"'
    '-c', 'web_search="disabled"'
    # Keep coaching separate from the user's coding session and configuration.
    '--ignore-user-config', '--ephemeral', '--sandbox', 'read-only'
    '--disable', 'shell_tool', '--disable', 'plugins'
    '--disable', 'hooks', '--disable', 'apps', '--disable', 'multi_agent'
    '--disable', 'code_mode_host', '--skip-git-repo-check'
    '--color', 'never'
)
$script:exitCode = 1

function Main {
    $ErrorActionPreference = 'Stop'
    $PSNativeCommandUseErrorActionPreference = $false
    $previousOutputEncoding = $OutputEncoding
    $OutputEncoding = $script:utf8Encoding
    $systemTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $allowedTempPrefix = $systemTempRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $correctionDirectory = $null

    try {
        # Validate both inputs before reading the draft or calling external programs.
        if (-not (Test-Path -LiteralPath $DraftPath -PathType Leaf)) {
            throw "Draft file does not exist: $DraftPath"
        }
        $draftFilePath = (Resolve-Path -LiteralPath $DraftPath).ProviderPath
        $vimExecutablePath = $env:CODEX_PROMPT_COACH_VIM
        if (-not $vimExecutablePath -or
            -not (Test-Path -LiteralPath $vimExecutablePath -PathType Leaf)) {
            throw 'Vim is not configured. Run enable.ps1 in this PowerShell session first.'
        }

        $draftText = [System.IO.File]::ReadAllText($draftFilePath, [System.Text.Encoding]::UTF8)
        $editorArguments = @($script:baseEditorArguments)
        $editorFiles = @($draftFilePath)

        # Empty drafts go straight to Vim. Coaching errors also fall back to draft-only editing.
        if (-not [string]::IsNullOrWhiteSpace($draftText)) {
            try {
                $correctionDirectory = Join-Path $systemTempRoot ('codex-coach-' + [guid]::NewGuid())
                [System.IO.Directory]::CreateDirectory($correctionDirectory) | Out-Null
                $suggestionFilePath = Join-Path $correctionDirectory 'suggestion.md'
                $invocationLogPath = Join-Path $correctionDirectory 'codex.log'

                # JSON encoding preserves the draft as text, including paths, quotes, and newlines.
                $coachingInstructions = [System.IO.File]::ReadAllText($script:coachPromptPath, [System.Text.Encoding]::UTF8)
                $encodedDraft = ConvertTo-Json -InputObject $draftText -Compress
                $coachingRequest = $coachingInstructions + "`n`nDRAFT (JSON-encoded text):`n" + $encodedDraft
                $codexApplication = Get-Command codex -CommandType Application -ErrorAction Stop |
                    Select-Object -First 1
                $codexArguments = @($script:baseCodexArguments) + @(
                    '-C', $correctionDirectory
                    '--output-last-message', $suggestionFilePath, '-'
                )

                Write-Host 'Coaching your prompt with gpt-6-luna (medium)...'
                $coachingRequest | & $codexApplication.Source @codexArguments > $invocationLogPath 2>&1
                if ($LASTEXITCODE -ne 0) {
                    $logTail = Get-Content -LiteralPath $invocationLogPath -Tail 3 -Encoding utf8
                    $failureDetails = $logTail -join ' '
                    throw "Codex exited with code $LASTEXITCODE. $failureDetails"
                }
                if (-not (Test-Path -LiteralPath $suggestionFilePath -PathType Leaf)) {
                    throw 'Codex returned no suggestion.'
                }
                $suggestionText = [System.IO.File]::ReadAllText($suggestionFilePath)
                if ([string]::IsNullOrWhiteSpace($suggestionText)) {
                    throw 'Codex returned no suggestion.'
                }

                # Add the suggestion only after a usable response exists; the draft remains editable.
                $editorArguments += @('-O', '-c', $script:suggestionPaneCommand)
                $editorFiles += $suggestionFilePath
            }
            catch {
                Write-Warning "Correction unavailable: $($_.Exception.Message) Opening the original draft in Vim."
            }
        }

        & $vimExecutablePath @editorArguments -- @editorFiles
        $script:exitCode = $LASTEXITCODE
        if ($script:exitCode -ne 0) {
            Write-Warning "Vim exited with code $script:exitCode. The coach has not overwritten your draft."
        }
    }
    catch {
        Write-Error $_ -ErrorAction Continue
    }
    finally {
        # Always restore encoding and remove only the correction directory inside the system temp root.
        $OutputEncoding = $previousOutputEncoding
        if ($correctionDirectory) {
            $cleanupPath = [System.IO.Path]::GetFullPath($correctionDirectory)
            if ($cleanupPath.StartsWith($allowedTempPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                Remove-Item -LiteralPath $cleanupPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# Entry point. Exit at script scope so the CMD wrapper receives Vim's exit code.
Main
exit $script:exitCode
