#Requires -Version 7.0
[CmdletBinding()]
param([string]$CoachRoot = (Join-Path $env:USERPROFILE '.codex-prompt-coach'))

# Opt-in test: makes one real gpt-6-luna call and drives the installed Vim in batch mode.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testDir = Join-Path $tempRoot ('coach-live-' + [guid]::NewGuid())
[System.IO.Directory]::CreateDirectory($testDir) | Out-Null
$originalProbeDir = $env:COACH_LIVE_DIR

try {
    & (Join-Path $CoachRoot 'enable.ps1')
    $env:COACH_LIVE_DIR = $testDir
    $env:COACH_LIVE_VIM = $env:CODEX_PROMPT_COACH_VIM
    $probe = @'
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
    Set-Content -LiteralPath (Join-Path $testDir 'editor-probe.ps1') -Value $probe -Encoding utf8
    $shim = "@echo off`r`npwsh.exe -NoLogo -NoProfile -File `"%~dp0editor-probe.ps1`" %*`r`nexit /b %ERRORLEVEL%`r`n"
    [System.IO.File]::WriteAllText((Join-Path $testDir 'editor-probe.cmd'), $shim, [System.Text.Encoding]::ASCII)
    $vimChecks = @'
if winnr('$') != 2 || &modifiable != 1 || &readonly != 0 | cquit 91 | endif
wincmd l
if &modifiable != 0 || &readonly != 1 | cquit 92 | endif
wincmd h
call setline(1, 'User saved this prompt: 영어')
call deletebufline('%', 2, '$')
wqa
'@
    Set-Content -LiteralPath (Join-Path $testDir 'verify.vim') -Value $vimChecks -Encoding utf8
    $draftPath = Join-Path $testDir 'draft.txt'
    $draft = @'
Please analyze `src\parser.ts` and 성능 저하의 원인을 찾아줘.
Keep `parseTokens`, `npm test`, and `const timeout = 5000;` unchanged.
'@
    [System.IO.File]::WriteAllText($draftPath, $draft, [System.Text.UTF8Encoding]::new($false))
    $env:CODEX_PROMPT_COACH_VIM = Join-Path $testDir 'editor-probe.cmd'
    & (Join-Path $CoachRoot 'bin\codex-prompt-coach.cmd') $draftPath
    if ($LASTEXITCODE -ne 0) { throw 'Live coach/editor test failed.' }
    $suggestion = [System.IO.File]::ReadAllText((Join-Path $testDir 'suggestion.md'))
    Write-Host $suggestion
    foreach ($literal in @('## Suggested Prompt', '## Learning Notes', 'src\parser.ts',
            'parseTokens', 'npm test', 'const timeout = 5000;')) {
        if (-not $suggestion.Contains($literal)) { throw "Suggestion did not preserve: $literal" }
    }
    if ($suggestion -notmatch '[가-힣]') { throw 'Korean learning notes are missing.' }
    $log = [System.IO.File]::ReadAllText((Join-Path $testDir 'execution.log'))
    foreach ($setting in @('model: gpt-6-luna', 'reasoning effort: medium', 'sandbox: read-only')) {
        if (-not $log.Contains($setting)) { throw "Live invocation did not confirm: $setting" }
    }
    if ([System.IO.File]::ReadAllText($draftPath).TrimEnd() -cne 'User saved this prompt: 영어') {
        throw 'Only the Vim edit should be returned.'
    }
    Write-Host 'PASS: live gpt-6-luna medium, technical literals, Korean notes, real Vim split/readonly/save.'
}
finally {
    & (Join-Path $CoachRoot 'enable.ps1') -Disable
    $env:COACH_LIVE_DIR = $originalProbeDir
    Remove-Item -LiteralPath 'Env:COACH_LIVE_VIM' -ErrorAction SilentlyContinue
    $cleanupPath = [System.IO.Path]::GetFullPath($testDir)
    $allowedPrefix = $tempRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if ($cleanupPath.StartsWith($allowedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $cleanupPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
