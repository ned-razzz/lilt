#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$CoachRoot = (Join-Path $env:USERPROFILE '.lilt')
)

# Opt-in end-to-end check: one real model call plus a real Vim edit/save in batch mode.
function Main {
    $ErrorActionPreference = 'Stop'
    $PSNativeCommandUseErrorActionPreference = $false
    $systemTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $script:tempDirectoryPrefix = $systemTempRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $sandboxPath = Join-Path $systemTempRoot ('lilt-live-' + [guid]::NewGuid())
    [System.IO.Directory]::CreateDirectory($sandboxPath) | Out-Null
    $previousProbeDirectory = $env:COACH_LIVE_DIR
    $previousProbeVim = $env:COACH_LIVE_VIM

    try {
        # Enable the installed coach, then redirect its Vim call through a probe that saves artifacts.
        & (Join-Path $CoachRoot 'enable.ps1')
        $env:COACH_LIVE_DIR = $sandboxPath
        $env:COACH_LIVE_VIM = $env:LILT_VIM
        # The probe captures the model output and invocation log before the coach removes its temp files.
        $vimProbeScript = @'
$ErrorActionPreference = 'Stop'
$nativeArgs = @($args)
$fileIndex = [array]::IndexOf($nativeArgs, '--')
$files = @($nativeArgs | Select-Object -Skip ($fileIndex + 1))
if ($files.Count -ne 2) { throw 'Live correction did not produce a suggestion.' }
Copy-Item -LiteralPath $files[1] -Destination (Join-Path $env:COACH_LIVE_DIR 'suggestion.md')
Copy-Item -LiteralPath (Join-Path (Split-Path $files[1] -Parent) 'codex.log') -Destination (Join-Path $env:COACH_LIVE_DIR 'execution.log')
$vimArgs = @($nativeArgs | Select-Object -First $fileIndex) +
    @('-es', '-S', (Join-Path $env:COACH_LIVE_DIR 'verify.vim').Replace('\', '/')) +
    @($nativeArgs | Select-Object -Skip $fileIndex)
& $env:COACH_LIVE_VIM @vimArgs
exit $LASTEXITCODE
'@
        Set-Content -LiteralPath (Join-Path $sandboxPath 'editor-probe.ps1') -Value $vimProbeScript -Encoding utf8
        $vimProbeShim = "@echo off`r`npwsh.exe -NoLogo -NoProfile -File `"%~dp0editor-probe.ps1`" %*`r`nexit /b %ERRORLEVEL%`r`n"
        [System.IO.File]::WriteAllText((Join-Path $sandboxPath 'editor-probe.cmd'), $vimProbeShim, [System.Text.Encoding]::ASCII)
        # Vim checks that the suggestion pane is read-only, then saves a known edit to the draft.
        $vimAssertions = @'
if winnr('$') != 2 || &modifiable != 1 || &readonly != 0 | cquit 91 | endif
wincmd l
if &modifiable != 0 || &readonly != 1 | cquit 92 | endif
wincmd h
call setline(1, 'User saved this prompt: 영어')
call deletebufline('%', 2, '$')
wqa
'@
        Set-Content -LiteralPath (Join-Path $sandboxPath 'verify.vim') -Value $vimAssertions -Encoding utf8
        $draftFilePath = Join-Path $sandboxPath 'draft.txt'
        $draftText = @'
Please analyze `src\parser.ts` and 성능 저하의 원인을 찾아줘.
Keep `parseTokens`, `npm test`, and `const timeout = 5000;` unchanged.
'@
        [System.IO.File]::WriteAllText($draftFilePath, $draftText, [System.Text.UTF8Encoding]::new($false))
        $env:LILT_VIM = Join-Path $sandboxPath 'editor-probe.cmd'
        & (Join-Path $CoachRoot 'bin\lilt.cmd') $draftFilePath
        if ($LASTEXITCODE -ne 0) { throw 'Live coach/editor test failed.' }
        # Confirm the model kept technical literals, returned Korean notes, and used expected settings.
        $suggestedPrompt = [System.IO.File]::ReadAllText((Join-Path $sandboxPath 'suggestion.md'))
        Write-Host $suggestedPrompt
        foreach ($literal in @('## Suggested Prompt', '## Learning Notes', '## Recommendations', 'src\parser.ts',
                'parseTokens', 'npm test', 'const timeout = 5000;')) {
            if (-not $suggestedPrompt.Contains($literal)) { throw "Suggestion did not preserve: $literal" }
        }
        if ($suggestedPrompt -notmatch '[가-힣]') { throw 'Korean learning notes are missing.' }
        $log = [System.IO.File]::ReadAllText((Join-Path $sandboxPath 'execution.log'))
        foreach ($setting in @('model: gpt-6-luna', 'reasoning effort: medium', 'sandbox: read-only')) {
            if (-not $log.Contains($setting)) { throw "Live invocation did not confirm: $setting" }
        }
        if ([System.IO.File]::ReadAllText($draftFilePath).TrimEnd() -cne 'User saved this prompt: 영어') {
            throw 'Only the Vim edit should be returned.'
        }
        Write-Host 'PASS: live gpt-6-luna medium, technical literals, Korean notes, real Vim split/readonly/save.'
    }
    finally {
        # Disable the temporary session and restore environment values that existed before the test.
        & (Join-Path $CoachRoot 'enable.ps1') -Disable
        $env:COACH_LIVE_DIR = $previousProbeDirectory
        if ($null -eq $previousProbeVim) {
            Remove-Item -LiteralPath 'Env:COACH_LIVE_VIM' -ErrorAction SilentlyContinue
        }
        else { $env:COACH_LIVE_VIM = $previousProbeVim }
        $cleanupPath = [System.IO.Path]::GetFullPath($sandboxPath)
        $allowedPrefix = $script:tempDirectoryPrefix
        if ($cleanupPath.StartsWith($allowedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $cleanupPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Entry point.
Main
