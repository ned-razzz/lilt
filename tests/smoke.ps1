#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repoRoot = Split-Path $PSScriptRoot -Parent
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testDir = Join-Path $tempRoot ('coach-tests-' + [guid]::NewGuid())
[System.IO.Directory]::CreateDirectory($testDir) | Out-Null
$savedEnvironment = @{}
foreach ($name in @('PATH', 'VISUAL', 'EDITOR', 'GIT_EDITOR', 'CODEX_PROMPT_COACH_VIM',
        'COACH_TEST_DIR', 'COACH_TEST_MODE', 'COACH_REAL_VIM', 'CODEX_PROMPT_COACH_ACTIVE')) {
    $savedEnvironment[$name] = [System.Environment]::GetEnvironmentVariable($name, 'Process')
}
$originalSession = Get-Variable CodexPromptCoachSession -Scope Global -ErrorAction SilentlyContinue
$passed = 0

function Assert($condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function Run-Coach([string]$mode, [string]$draftText) {
    foreach ($name in @('codex.json', 'vim.json')) {
        Remove-Item -LiteralPath (Join-Path $testDir $name) -Force -ErrorAction SilentlyContinue
    }
    [System.IO.File]::WriteAllText($draftPath, $draftText, [System.Text.UTF8Encoding]::new($false))
    $env:COACH_TEST_MODE = $mode
    & $wrapperPath $draftPath | Out-Host
    $script:coachExitCode = $LASTEXITCODE
    $script:vimRecord = Get-Content -LiteralPath (Join-Path $testDir 'vim.json') -Raw | ConvertFrom-Json
    $script:codexRecord = if (Test-Path -LiteralPath (Join-Path $testDir 'codex.json')) {
        Get-Content -LiteralPath (Join-Path $testDir 'codex.json') -Raw | ConvertFrom-Json
    } else { $null }
}

try {
    $env:CODEX_PROMPT_COACH_ACTIVE = $null
    if ($originalSession) { Remove-Variable CodexPromptCoachSession -Scope Global }
    $realVim = Join-Path (Split-Path (Get-Command git -CommandType Application).Source -Parent) '..\usr\bin\vim.exe'
    if (-not (Test-Path -LiteralPath $realVim)) {
        $realVim = (Get-Command vim -CommandType Application -ErrorAction Stop).Source
    }
    $env:COACH_REAL_VIM = (Resolve-Path -LiteralPath $realVim).ProviderPath
    $fixtureDir = Join-Path $testDir '한글 space [fixtures]'
    [System.IO.Directory]::CreateDirectory($fixtureDir) | Out-Null
    $draftPath = Join-Path $fixtureDir 'draft [한글].txt'
    $wrapperPath = Join-Path $repoRoot 'src\bin\codex-prompt-coach.cmd'
    $env:COACH_TEST_DIR = $testDir
    $env:PATH = $fixtureDir + ';' + $env:PATH
    $env:CODEX_PROMPT_COACH_VIM = Join-Path $fixtureDir 'vim.cmd'

    $fakeNative = @'
$ErrorActionPreference = 'Stop'
$tool = $args[0]
$nativeArgs = @($args | Select-Object -Skip 1)
$record = @{ Args = $nativeArgs }
if ($tool -eq 'codex') {
    [Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
    $record.Input = [Console]::In.ReadToEnd()
    $outputIndex = [array]::IndexOf($nativeArgs, '--output-last-message')
    $record.Output = $nativeArgs[$outputIndex + 1]
    $record.WorkDir = $nativeArgs[[array]::IndexOf($nativeArgs, '-C') + 1]
    $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $env:COACH_TEST_DIR 'codex.json') -Encoding utf8
    if ($env:COACH_TEST_MODE -eq 'fail') { [Console]::Error.WriteLine('Fake model unavailable'); exit 23 }
    if ($env:COACH_TEST_MODE -eq 'missing') { exit 0 }
    $suggestion = if ($env:COACH_TEST_MODE -eq 'empty') { ' ' } else {
        "## Suggested Prompt`nPlease fix the code.`n`n## Learning Notes`n- 한국어를 영어로 옮겼습니다."
    }
    [IO.File]::WriteAllText($record.Output, $suggestion, [Text.UTF8Encoding]::new($false))
    exit 0
}
$fileIndex = [array]::IndexOf($nativeArgs, '--')
$record.Files = @($nativeArgs | Select-Object -Skip ($fileIndex + 1))
$record.Draft = [IO.File]::ReadAllText($record.Files[0])
$record.Suggestion = if ($record.Files.Count -eq 2) { [IO.File]::ReadAllText($record.Files[1]) } else { $null }
$record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $env:COACH_TEST_DIR 'vim.json') -Encoding utf8
if ($env:COACH_TEST_MODE -eq 'editor-fail') { exit 7 }
if ($env:COACH_TEST_MODE -eq 'edit') {
    [IO.File]::WriteAllText($record.Files[0], 'User edited this draft: 직접 수정', [Text.UTF8Encoding]::new($false))
}
if ($env:COACH_TEST_MODE -eq 'real-editor') {
    $vimLog = Join-Path $env:COACH_TEST_DIR 'vim.log'
    $realArgs = @($nativeArgs | Select-Object -First $fileIndex) +
        @('-es', ('-V1' + $vimLog), '-S', (Join-Path $env:COACH_TEST_DIR 'verify-editor.vim').Replace('\', '/')) +
        @($nativeArgs | Select-Object -Skip $fileIndex)
    & $env:COACH_REAL_VIM @realArgs
    $vimExitCode = $LASTEXITCODE
    if ($vimExitCode -ne 0) { Get-Content -LiteralPath $vimLog | Out-Host }
    exit $vimExitCode
}
exit 0
'@
    Set-Content -LiteralPath (Join-Path $fixtureDir 'fake-native.ps1') -Value $fakeNative -Encoding utf8
    foreach ($tool in @('codex', 'vim')) {
        $shim = "@echo off`r`npwsh.exe -NoLogo -NoProfile -File `"%~dp0fake-native.ps1`" $tool %*`r`nexit /b %ERRORLEVEL%`r`n"
        [System.IO.File]::WriteAllText((Join-Path $fixtureDir "$tool.cmd"), $shim, [System.Text.Encoding]::ASCII)
    }
    $mixedDraft = "Please fix 성능 문제 in src\parser.ts.`nKeep `"Identifier_42`" and `"</DRAFT>`" unchanged."

    Run-Coach 'success' $mixedDraft
    Assert ($coachExitCode -eq 0 -and $vimRecord.Files.Count -eq 2) 'Successful correction must open two files.'
    Assert ([System.IO.File]::ReadAllText($draftPath) -ceq $mixedDraft) 'The coach overwrote the original draft.'
    Assert ($codexRecord.Input.Contains('성능 문제') -and $vimRecord.Suggestion.Contains('한국어')) 'UTF-8 was corrupted.'
    $configArgs = @($codexRecord.Args | ForEach-Object { $_.Replace('"', '') })
    Assert ($configArgs -contains 'gpt-6-luna' -and $configArgs -contains 'model_reasoning_effort=medium') 'Wrong correction model or effort.'
    foreach ($arg in @('--ephemeral', 'read-only', '--skip-git-repo-check', '--ignore-user-config',
            'shell_tool', 'plugins', 'hooks', 'apps', 'multi_agent', 'code_mode_host')) {
        Assert ($configArgs -contains $arg) "Missing isolation argument: $arg"
    }
    Assert ($vimRecord.Args -contains '--clean' -and $vimRecord.Args -contains '-O') 'Vim split or clean mode is missing.'
    Assert (-not (Test-Path -LiteralPath $codexRecord.WorkDir)) 'Correction temp directory was not removed.'
    $passed++

    foreach ($mode in @('fail', 'empty', 'missing')) {
        Run-Coach $mode $mixedDraft
        Assert ($coachExitCode -eq 0 -and $vimRecord.Files.Count -eq 1) "$mode must fall back to the original editor."
        Assert ([System.IO.File]::ReadAllText($draftPath) -ceq $mixedDraft) "$mode changed the draft."
        Assert (-not (Test-Path -LiteralPath $codexRecord.WorkDir)) "$mode did not clean up its temp directory."
        $passed++
    }

    Run-Coach 'blank' ''
    Assert ($coachExitCode -eq 0 -and $null -eq $codexRecord -and $vimRecord.Files.Count -eq 1) 'Empty draft must skip Codex.'
    $passed++
    Run-Coach 'edit' $mixedDraft
    Assert ([System.IO.File]::ReadAllText($draftPath) -ceq 'User edited this draft: 직접 수정') 'Only user edits should be retained.'
    $passed++
    Run-Coach 'editor-fail' $mixedDraft
    Assert ($coachExitCode -eq 7 -and [System.IO.File]::ReadAllText($draftPath) -ceq $mixedDraft) 'CMD must propagate the editor failure without overwriting the draft.'
    $passed++
    & $wrapperPath (Join-Path $fixtureDir 'nonexistent.txt') 2>&1 | Out-Null
    Assert ($LASTEXITCODE -ne 0) 'Invalid draft path must fail.'
    $passed++

    $profileExisted = Test-Path -LiteralPath $PROFILE
    $profileBefore = if ($profileExisted) { [System.IO.File]::ReadAllText($PROFILE) } else { $null }
    $installPath = Join-Path $testDir '설치 space [coach]'
    $testProfile = Join-Path $testDir 'profile.ps1'
    $existingProfileText = "# existing 설정`r`n"
    [System.IO.File]::WriteAllText($testProfile, $existingProfileText)
    & (Join-Path $repoRoot 'scripts\install.ps1') -InstallPath $installPath -VimPath $env:CODEX_PROMPT_COACH_VIM -ProfilePath $testProfile
    & (Join-Path $repoRoot 'scripts\install.ps1') -InstallPath $installPath -VimPath $env:CODEX_PROMPT_COACH_VIM -ProfilePath $testProfile
    $managedProfile = [System.IO.File]::ReadAllText($testProfile)
    Assert (([regex]::Matches($managedProfile, '# >>> Codex Prompt Coach >>>')).Count -eq 1) 'Repeated installation duplicated the profile block.'
    Assert ($managedProfile.StartsWith($existingProfileText)) 'Installer changed existing profile settings.'
    Assert ([System.IO.File]::ReadAllText($testProfile + '.codex-prompt-coach.bak') -ceq $existingProfileText) 'Profile backup did not preserve the original.'
    Assert ((Test-Path -LiteralPath $PROFILE) -eq $profileExisted) 'Installer changed profile existence.'
    if ($profileExisted) { Assert ([System.IO.File]::ReadAllText($PROFILE) -ceq $profileBefore) 'Installer changed the profile.' }
    foreach ($file in @('enable.ps1', 'bin\codex-prompt-coach.cmd', 'bin\codex-prompt-coach.ps1', 'prompts\coach-prompt.txt')) {
        Assert (Test-Path -LiteralPath (Join-Path $installPath $file)) "Installed file is missing: $file"
    }
    $passed++

    . $testProfile
    Assert ($global:CodexPromptCoachConfiguredVim -ceq $env:CODEX_PROMPT_COACH_VIM) 'The configured Vim path was not retained by the profile.'
    $autoVisual = $env:VISUAL
    $autoGitEditor = $env:GIT_EDITOR
    $autoVim = $env:CODEX_PROMPT_COACH_VIM
    $version = codex --version | Out-String
    Assert ($LASTEXITCODE -eq 0 -and $version -match 'codex-cli') 'Automatic launcher did not forward --version to the real Codex CLI.'
    Assert ($env:VISUAL -ceq $autoVisual -and $env:GIT_EDITOR -ceq $autoGitEditor -and $env:CODEX_PROMPT_COACH_VIM -ceq $autoVim) 'Automatic launcher did not restore the editor environment.'
    Assert ($null -eq $env:CODEX_PROMPT_COACH_ACTIVE) 'Automatic launcher leaked its child-process marker.'
    $passed++

    codex --coach-invalid-option 2>&1 | Out-Null
    Assert ($LASTEXITCODE -ne 0 -and $env:VISUAL -ceq $autoVisual -and $env:GIT_EDITOR -ceq $autoGitEditor) 'Failed Codex invocation did not preserve its exit code and restore the editor.'
    $passed++

    & (Join-Path $installPath 'enable.ps1') -VimPath $autoVim -Quiet
    $manuallyEnabledVisual = $env:VISUAL
    codex --version | Out-Null
    Assert ($LASTEXITCODE -eq 0 -and $env:VISUAL -ceq $manuallyEnabledVisual -and (Get-Variable CodexPromptCoachSession -Scope Global -ErrorAction SilentlyContinue)) 'Automatic launcher disabled a manually enabled session.'
    & (Join-Path $installPath 'enable.ps1') -Disable -Quiet
    $passed++

    $env:CODEX_PROMPT_COACH_ACTIVE = '1'
    $version = codex --version | Out-String
    Assert ($LASTEXITCODE -eq 0 -and $version -match 'codex-cli' -and $env:VISUAL -ceq $autoVisual) 'Nested Codex invocation did not bypass the launcher.'
    $env:CODEX_PROMPT_COACH_ACTIVE = $null
    $passed++

    & (Join-Path $installPath 'install.ps1') -Uninstall -ProfilePath $testProfile
    Assert ([System.IO.File]::ReadAllText($testProfile) -ceq $existingProfileText) 'Removing the launcher changed existing profile settings.'
    $passed++

    $env:VISUAL = 'original-visual'
    $env:GIT_EDITOR = 'existing-git-editor --wait'
    $oldVim = $env:CODEX_PROMPT_COACH_VIM
    & (Join-Path $installPath 'enable.ps1') -VimPath $oldVim
    $enabledVisual = $env:VISUAL
    Assert ($env:GIT_EDITOR -ceq 'existing-git-editor --wait') 'Existing GIT_EDITOR was overwritten.'
    & (Join-Path $installPath 'enable.ps1') -VimPath $oldVim
    Assert ($env:VISUAL -ceq $enabledVisual) 'Repeated activation is not stable.'
    & (Join-Path $installPath 'enable.ps1') -Disable
    Assert ($env:VISUAL -ceq 'original-visual' -and $env:GIT_EDITOR -ceq 'existing-git-editor --wait') 'Deactivation did not restore the original environment.'
    Assert ($env:CODEX_PROMPT_COACH_VIM -ceq $oldVim) 'Deactivation did not restore the Vim path.'
    $passed++

    $env:GIT_EDITOR = $null
    $expectedGitEditor = git var GIT_EDITOR
    & (Join-Path $installPath 'enable.ps1') -VimPath $oldVim
    Assert ($env:GIT_EDITOR -ceq $expectedGitEditor -and (git var GIT_EDITOR) -ceq $expectedGitEditor) 'Git editor changed after activation.'
    & (Join-Path $installPath 'enable.ps1') -Disable
    Assert ($null -eq $env:GIT_EDITOR) 'Unset GIT_EDITOR was not restored.'
    $passed++

    & pwsh -NoProfile -File (Join-Path $installPath 'enable.ps1') -VimPath $oldVim
    Assert ($env:VISUAL -ceq 'original-visual' -and $null -eq $env:GIT_EDITOR) 'Child-session activation leaked into the parent.'
    $passed++

    $vimChecks = @'
if winnr('$') != 2 | cquit 90 | endif
if &modifiable != 1 || &readonly != 0 | cquit 91 | endif
wincmd l
if &modifiable != 0 || &readonly != 1 | cquit 92 | endif
wincmd h
call setline(1, 'Edited in Vim: 영어 UTF-8')
call deletebufline('%', 2, '$')
wqa
'@
    Set-Content -LiteralPath (Join-Path $testDir 'verify-editor.vim') -Value $vimChecks -Encoding utf8
    $wrapperPath = Join-Path $installPath 'bin\codex-prompt-coach.cmd'
    Run-Coach 'real-editor' $mixedDraft
    Assert ($coachExitCode -eq 0) 'Real Vim split, readonly, or saving validation failed.'
    Assert ([System.IO.File]::ReadAllText($draftPath).TrimEnd() -ceq 'Edited in Vim: 영어 UTF-8') 'Vim did not save only the edited draft in UTF-8.'
    $passed++
    Write-Host "PASS: $passed scenarios, including real Vim split/readonly/save and installed paths with spaces and Korean."
}
finally {
    foreach ($name in $savedEnvironment.Keys) {
        if ($null -eq $savedEnvironment[$name]) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        }
        else {
            [System.Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
        }
    }
    Remove-Variable CodexPromptCoachSession -Scope Global -ErrorAction SilentlyContinue
    if ($originalSession) { $global:CodexPromptCoachSession = $originalSession.Value }
    $cleanupPath = [System.IO.Path]::GetFullPath($testDir)
    $allowedPrefix = $tempRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if ($cleanupPath.StartsWith($allowedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $cleanupPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
