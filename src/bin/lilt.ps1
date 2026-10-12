#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$DraftPath
)

# Script-wide configuration keeps the invocation details out of Main's execution flow.
$script:utf8Encoding = [System.Text.UTF8Encoding]::new($false)
$script:coachPromptPath = Join-Path $PSScriptRoot '..\prompts\editing-feedback-prompt.txt'
$script:baseEditorArguments = @(
    '--clean', '-n', '--cmd', 'set encoding=utf-8 nomodeline'
    '-c', 'setlocal fileencoding=utf-8'
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
    $coachProcess = $null

    try {
        # Validate both inputs before reading the draft or calling external programs.
        if (-not (Test-Path -LiteralPath $DraftPath -PathType Leaf)) {
            throw "Draft file does not exist: $DraftPath"
        }
        $draftFilePath = (Resolve-Path -LiteralPath $DraftPath).ProviderPath
        $vimExecutablePath = $env:LILT_VIM
        if (-not $vimExecutablePath -or
            -not (Test-Path -LiteralPath $vimExecutablePath -PathType Leaf)) {
            throw 'Vim is not configured. Run enable.ps1 in this PowerShell session first.'
        }

        $draftText = [System.IO.File]::ReadAllText($draftFilePath, [System.Text.Encoding]::UTF8)
        $editorArguments = @($script:baseEditorArguments)
        $editorFiles = @($draftFilePath)

        # Empty drafts go straight to Vim; nonempty drafts get a live suggestion pane.
        if (-not [string]::IsNullOrWhiteSpace($draftText)) {
            try {
                $correctionDirectory = Join-Path $systemTempRoot ('lilt-' + [guid]::NewGuid())
                [System.IO.Directory]::CreateDirectory($correctionDirectory) | Out-Null
                $suggestionFilePath = Join-Path $correctionDirectory 'suggestion.md'

                # JSON encoding preserves the draft as text, including paths, quotes, and newlines.
                $coachingInstructions = [System.IO.File]::ReadAllText($script:coachPromptPath, [System.Text.Encoding]::UTF8)
                $encodedDraft = ConvertTo-Json -InputObject $draftText -Compress
                $coachingRequest = $coachingInstructions + "`n`nDRAFT (JSON-encoded text):`n" + $encodedDraft
                $codexApplication = Get-Command codex -CommandType Application -ErrorAction Stop |
                    Select-Object -First 1
                [IO.File]::WriteAllText((Join-Path $correctionDirectory 'request.txt'), $coachingRequest, $script:utf8Encoding)
                [IO.File]::WriteAllText($suggestionFilePath, "Coaching...`nYou can edit your draft while the suggestion is prepared.", $script:utf8Encoding)

                # A hidden worker owns the model call; Vim keeps the terminal immediately.
                $processInfo = [Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'))
                $processInfo.UseShellExecute = $false
                $processInfo.CreateNoWindow = $true
                foreach ($argument in @('-NoLogo', '-NoProfile', '-File', (Join-Path $PSScriptRoot 'coach.ps1'),
                        '-CorrectionDirectory', $correctionDirectory, '-CodexPath', $codexApplication.Source)) {
                    $processInfo.ArgumentList.Add($argument)
                }
                $coachProcess = [Diagnostics.Process]::Start($processInfo)
                $editorArguments += @('-O', '-S', (Join-Path $PSScriptRoot 'suggestion.vim').Replace('\', '/'))
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
        # Leaving Vim cancels unfinished coaching, including its native child process.
        if ($coachProcess) {
            if (-not $coachProcess.HasExited) {
                $coachProcess.Kill($true)
                $coachProcess.WaitForExit()
            }
            $coachProcess.Dispose()
        }
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
