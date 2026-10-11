#Requires -Version 7.0
# Exercises the installed flow with fake Codex/Vim commands, then checks real Vim behavior.
# Keep helper functions visible while putting the execution flow in Main.
function Test-Condition($condition, [string]$message) {
    if (-not $condition) { throw $message }
}

function Invoke-CoachScenario([string]$scenarioName, [string]$draftText) {
    # Each run starts with fresh captures so assertions only inspect this scenario.
    foreach ($name in @('codex.json', 'vim.json')) {
        Remove-Item -LiteralPath (Join-Path $script:sandboxPath $name) -Force -ErrorAction SilentlyContinue
    }
    [System.IO.File]::WriteAllText($script:draftFilePath, $draftText, [System.Text.UTF8Encoding]::new($false))
    $env:COACH_TEST_MODE = $scenarioName
    & $script:coachWrapperPath $script:draftFilePath | Out-Host
    $script:coachExitCode = $LASTEXITCODE
    $script:editorCall = Get-Content -LiteralPath (Join-Path $script:sandboxPath 'vim.json') -Raw | ConvertFrom-Json
    $script:codexCall = if (Test-Path -LiteralPath (Join-Path $script:sandboxPath 'codex.json')) {
        Get-Content -LiteralPath (Join-Path $script:sandboxPath 'codex.json') -Raw | ConvertFrom-Json
    } else { $null }
}

function Main {
    $ErrorActionPreference = 'Stop'
    $PSNativeCommandUseErrorActionPreference = $false
    $repositoryRoot = Split-Path $PSScriptRoot -Parent
    $systemTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $script:tempDirectoryPrefix = $systemTempRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

    # Helpers share these paths through script scope instead of process-wide global variables.
    $script:sandboxPath = Join-Path $systemTempRoot ('lilt-tests-' + [guid]::NewGuid())
    [System.IO.Directory]::CreateDirectory($script:sandboxPath) | Out-Null
    $script:draftFilePath = $null
    $script:coachWrapperPath = $null

    $originalEnvironment = @{}
    foreach ($name in @('PATH', 'VISUAL', 'EDITOR', 'GIT_EDITOR', 'LILT_VIM',
            'COACH_TEST_DIR', 'COACH_TEST_MODE', 'COACH_REAL_VIM', 'LILT_ACTIVE')) {
        $originalEnvironment[$name] = [System.Environment]::GetEnvironmentVariable($name, 'Process')
    }
    $previousCoachSession = Get-Variable LiltSession -Scope Global -ErrorAction SilentlyContinue
    $passedScenarioCount = 0

    try {
        # Arrange an isolated PATH where the coach finds our fake native commands first.
        $env:LILT_ACTIVE = $null
        if ($previousCoachSession) { Remove-Variable LiltSession -Scope Global }
        $realVimPath = Join-Path (Split-Path (Get-Command git -CommandType Application).Source -Parent) '..\usr\bin\vim.exe'
        if (-not (Test-Path -LiteralPath $realVimPath)) {
            $realVimPath = (Get-Command vim -CommandType Application -ErrorAction Stop).Source
        }
        $env:COACH_REAL_VIM = (Resolve-Path -LiteralPath $realVimPath).ProviderPath
        $fakeToolDirectory = Join-Path $script:sandboxPath '한글 space [fixtures]'
        [System.IO.Directory]::CreateDirectory($fakeToolDirectory) | Out-Null
        $script:draftFilePath = Join-Path $fakeToolDirectory 'draft [한글].txt'
        $script:coachWrapperPath = Join-Path $repositoryRoot 'src\bin\lilt.cmd'
        $env:COACH_TEST_DIR = $script:sandboxPath
        $env:PATH = $fakeToolDirectory + ';' + $env:PATH
        $env:LILT_VIM = Join-Path $fakeToolDirectory 'vim.cmd'

        # These shims record arguments and input, then simulate success, failure, or edits.
        $fakeNative = @'
$ErrorActionPreference = 'Stop'
$tool = $args[0]
$nativeArgs = @($args | Select-Object -Skip 1)
$record = @{ Args = $nativeArgs }
if ($tool -eq 'codex') {
    # Capture the prompt and arguments, then simulate model success or failure by scenario.
    [Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
    $record.Input = [Console]::In.ReadToEnd()
    $outputIndex = [array]::IndexOf($nativeArgs, '--output-last-message')
    $record.Output = $nativeArgs[$outputIndex + 1]
    $record.WorkDir = $nativeArgs[[array]::IndexOf($nativeArgs, '-C') + 1]
    $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $env:COACH_TEST_DIR 'codex.json') -Encoding utf8
    if ($env:COACH_TEST_MODE -eq 'codex-fails') { [Console]::Error.WriteLine('Fake model unavailable'); exit 23 }
    if ($env:COACH_TEST_MODE -eq 'suggestion-missing') { exit 0 }
    $suggestion = if ($env:COACH_TEST_MODE -eq 'suggestion-empty') { ' ' } else {
        "## Suggested Prompt`nPlease fix the code.`n`n## Learning Notes`n- 한국어를 영어로 옮겼습니다."
    }
    [IO.File]::WriteAllText($record.Output, $suggestion, [Text.UTF8Encoding]::new($false))
    exit 0
}
# Capture the editor's files, simulate a user edit, or forward the call to real Vim.
$fileIndex = [array]::IndexOf($nativeArgs, '--')
$record.Files = @($nativeArgs | Select-Object -Skip ($fileIndex + 1))
$record.Draft = [IO.File]::ReadAllText($record.Files[0])
$record.Suggestion = if ($record.Files.Count -eq 2) { [IO.File]::ReadAllText($record.Files[1]) } else { $null }
$record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $env:COACH_TEST_DIR 'vim.json') -Encoding utf8
if ($env:COACH_TEST_MODE -eq 'editor-exits-with-error') { exit 7 }
if ($env:COACH_TEST_MODE -eq 'user-edits-draft') {
    [IO.File]::WriteAllText($record.Files[0], 'User edited this draft: 직접 수정', [Text.UTF8Encoding]::new($false))
}
if ($env:COACH_TEST_MODE -eq 'run-real-vim') {
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
        Set-Content -LiteralPath (Join-Path $fakeToolDirectory 'fake-native.ps1') -Value $fakeNative -Encoding utf8
        foreach ($tool in @('codex', 'vim')) {
            $shim = "@echo off`r`npwsh.exe -NoLogo -NoProfile -File `"%~dp0fake-native.ps1`" $tool %*`r`nexit /b %ERRORLEVEL%`r`n"
            [System.IO.File]::WriteAllText((Join-Path $fakeToolDirectory "$tool.cmd"), $shim, [System.Text.Encoding]::ASCII)
        }
        $mixedDraft = "Please fix 성능 문제 in src\parser.ts.`nKeep `"Identifier_42`" and `"</DRAFT>`" unchanged."

        # A successful correction preserves the draft and passes the expected options to both tools.
        Invoke-CoachScenario 'success' $mixedDraft
        Test-Condition ($coachExitCode -eq 0 -and $editorCall.Files.Count -eq 2) 'Successful correction must open two files.'
        Test-Condition ([System.IO.File]::ReadAllText($draftFilePath) -ceq $mixedDraft) 'The coach overwrote the original draft.'
        Test-Condition ($codexCall.Input.Contains('성능 문제') -and $editorCall.Suggestion.Contains('한국어')) 'UTF-8 was corrupted.'
        $configArgs = @($codexCall.Args | ForEach-Object { $_.Replace('"', '') })
        Test-Condition ($configArgs -contains 'gpt-6-luna' -and $configArgs -contains 'model_reasoning_effort=medium') 'Wrong correction model or effort.'
        foreach ($arg in @('--ephemeral', 'read-only', '--skip-git-repo-check', '--ignore-user-config',
                'shell_tool', 'plugins', 'hooks', 'apps', 'multi_agent', 'code_mode_host')) {
            Test-Condition ($configArgs -contains $arg) "Missing isolation argument: $arg"
        }
        Test-Condition ($editorCall.Args -contains '--clean' -and $editorCall.Args -contains '-O') 'Vim split or clean mode is missing.'
        Test-Condition (-not (Test-Path -LiteralPath $codexCall.WorkDir)) 'Correction temp directory was not removed.'
        $passedScenarioCount++

        # Model failures and unusable responses should still open the original draft for editing.
        foreach ($scenarioName in @('codex-fails', 'suggestion-empty', 'suggestion-missing')) {
            Invoke-CoachScenario $scenarioName $mixedDraft
            Test-Condition ($coachExitCode -eq 0 -and $editorCall.Files.Count -eq 1) "$scenarioName must fall back to the original editor."
            Test-Condition ([System.IO.File]::ReadAllText($draftFilePath) -ceq $mixedDraft) "$scenarioName changed the draft."
            Test-Condition (-not (Test-Path -LiteralPath $codexCall.WorkDir)) "$scenarioName did not clean up its temp directory."
            $passedScenarioCount++
        }

        # Empty drafts skip Codex; Vim edits are returned; Vim failures keep their exit code.
        Invoke-CoachScenario 'empty-draft' ''
        Test-Condition ($coachExitCode -eq 0 -and $null -eq $codexCall -and $editorCall.Files.Count -eq 1) 'Empty draft must skip Codex.'
        $passedScenarioCount++
        Invoke-CoachScenario 'user-edits-draft' $mixedDraft
        Test-Condition ([System.IO.File]::ReadAllText($draftFilePath) -ceq 'User edited this draft: 직접 수정') 'Only user edits should be retained.'
        $passedScenarioCount++
        Invoke-CoachScenario 'editor-exits-with-error' $mixedDraft
        Test-Condition ($coachExitCode -eq 7 -and [System.IO.File]::ReadAllText($draftFilePath) -ceq $mixedDraft) 'CMD must propagate the editor failure without overwriting the draft.'
        $passedScenarioCount++
        & $coachWrapperPath (Join-Path $fakeToolDirectory 'nonexistent.txt') 2>&1 | Out-Null
        Test-Condition ($LASTEXITCODE -ne 0) 'Invalid draft path must fail.'
        $passedScenarioCount++

        # Install twice into a temporary profile to check copying, backup, and idempotence.
        $profileExisted = Test-Path -LiteralPath $PROFILE
        $profileBefore = if ($profileExisted) { [System.IO.File]::ReadAllText($PROFILE) } else { $null }
        $installPath = Join-Path $script:sandboxPath '설치 space [coach]'
        $testProfile = Join-Path $script:sandboxPath 'profile.ps1'
        $existingProfileText = "# existing 설정`r`n"
        [System.IO.File]::WriteAllText($testProfile, $existingProfileText)
        $script:installerScriptPath = Join-Path $repositoryRoot 'scripts\install.ps1'
        $script:installerParameters = @{
            InstallPath = $installPath
            VimPath = $env:LILT_VIM
            ProfilePath = $testProfile
        }
        & $script:installerScriptPath @script:installerParameters
        & $script:installerScriptPath @script:installerParameters
        $managedProfile = [System.IO.File]::ReadAllText($testProfile)
        Test-Condition (([regex]::Matches($managedProfile, '# >>> Lilt >>>')).Count -eq 1) 'Repeated installation duplicated the profile block.'
        Test-Condition ($managedProfile.StartsWith($existingProfileText)) 'Installer changed existing profile settings.'
        Test-Condition ([System.IO.File]::ReadAllText($testProfile + '.lilt.bak') -ceq $existingProfileText) 'Profile backup did not preserve the original.'
        Test-Condition ((Test-Path -LiteralPath $PROFILE) -eq $profileExisted) 'Installer changed profile existence.'
        if ($profileExisted) { Test-Condition ([System.IO.File]::ReadAllText($PROFILE) -ceq $profileBefore) 'Installer changed the profile.' }
        foreach ($file in @('enable.ps1', 'bin\lilt.cmd', 'bin\lilt.ps1', 'prompts\editing-feedback-prompt.txt')) {
            Test-Condition (Test-Path -LiteralPath (Join-Path $installPath $file)) "Installed file is missing: $file"
        }
        $passedScenarioCount++

        # Load the test profile and exercise automatic, nested, and manually enabled sessions.
        . $testProfile
        Test-Condition ($global:LiltConfiguredVim -ceq $env:LILT_VIM) 'The configured Vim path was not retained by the profile.'
        $autoVisual = $env:VISUAL
        $autoGitEditor = $env:GIT_EDITOR
        $autoVim = $env:LILT_VIM
        $version = codex --version | Out-String
        Test-Condition ($LASTEXITCODE -eq 0 -and $version -match 'codex-cli') 'Automatic launcher did not forward --version to the real Codex CLI.'
        Test-Condition ($env:VISUAL -ceq $autoVisual -and $env:GIT_EDITOR -ceq $autoGitEditor -and $env:LILT_VIM -ceq $autoVim) 'Automatic launcher did not restore the editor environment.'
        Test-Condition ($null -eq $env:LILT_ACTIVE) 'Automatic launcher leaked its child-process marker.'
        $passedScenarioCount++

        codex --coach-invalid-option 2>&1 | Out-Null
        Test-Condition ($LASTEXITCODE -ne 0 -and $env:VISUAL -ceq $autoVisual -and $env:GIT_EDITOR -ceq $autoGitEditor) 'Failed Codex invocation did not preserve its exit code and restore the editor.'
        $passedScenarioCount++

        & (Join-Path $installPath 'enable.ps1') -VimPath $autoVim -Quiet
        $manuallyEnabledVisual = $env:VISUAL
        codex --version | Out-Null
        Test-Condition ($LASTEXITCODE -eq 0 -and $env:VISUAL -ceq $manuallyEnabledVisual -and (Get-Variable LiltSession -Scope Global -ErrorAction SilentlyContinue)) 'Automatic launcher disabled a manually enabled session.'
        & (Join-Path $installPath 'enable.ps1') -Disable -Quiet
        $passedScenarioCount++

        $env:LILT_ACTIVE = '1'
        $version = codex --version | Out-String
        Test-Condition ($LASTEXITCODE -eq 0 -and $version -match 'codex-cli' -and $env:VISUAL -ceq $autoVisual) 'Nested Codex invocation did not bypass the launcher.'
        $env:LILT_ACTIVE = $null
        $passedScenarioCount++

        # Uninstall must remove only Lilt's managed block from the profile.
        & (Join-Path $installPath 'install.ps1') -Uninstall -ProfilePath $testProfile
        Test-Condition ([System.IO.File]::ReadAllText($testProfile) -ceq $existingProfileText) 'Removing the launcher changed existing profile settings.'
        $passedScenarioCount++

        # Session activation must preserve existing values and restore originally unset values.
        $env:VISUAL = 'original-visual'
        $env:GIT_EDITOR = 'existing-git-editor --wait'
        $oldVim = $env:LILT_VIM
        & (Join-Path $installPath 'enable.ps1') -VimPath $oldVim
        $enabledVisual = $env:VISUAL
        Test-Condition ($env:GIT_EDITOR -ceq 'existing-git-editor --wait') 'Existing GIT_EDITOR was overwritten.'
        & (Join-Path $installPath 'enable.ps1') -VimPath $oldVim
        Test-Condition ($env:VISUAL -ceq $enabledVisual) 'Repeated activation is not stable.'
        & (Join-Path $installPath 'enable.ps1') -Disable
        Test-Condition ($env:VISUAL -ceq 'original-visual' -and $env:GIT_EDITOR -ceq 'existing-git-editor --wait') 'Deactivation did not restore the original environment.'
        Test-Condition ($env:LILT_VIM -ceq $oldVim) 'Deactivation did not restore the Vim path.'
        $passedScenarioCount++

        $env:GIT_EDITOR = $null
        $expectedGitEditor = git var GIT_EDITOR
        & (Join-Path $installPath 'enable.ps1') -VimPath $oldVim
        Test-Condition ($env:GIT_EDITOR -ceq $expectedGitEditor -and (git var GIT_EDITOR) -ceq $expectedGitEditor) 'Git editor changed after activation.'
        & (Join-Path $installPath 'enable.ps1') -Disable
        Test-Condition ($null -eq $env:GIT_EDITOR) 'Unset GIT_EDITOR was not restored.'
        $passedScenarioCount++

        & pwsh -NoProfile -File (Join-Path $installPath 'enable.ps1') -VimPath $oldVim
        Test-Condition ($env:VISUAL -ceq 'original-visual' -and $null -eq $env:GIT_EDITOR) 'Child-session activation leaked into the parent.'
        $passedScenarioCount++

        # Finally, drive real Vim in batch mode to verify the split, read-only suggestion, and save.
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
        Set-Content -LiteralPath (Join-Path $script:sandboxPath 'verify-editor.vim') -Value $vimChecks -Encoding utf8
        $script:coachWrapperPath = Join-Path $installPath 'bin\lilt.cmd'
        Invoke-CoachScenario 'run-real-vim' $mixedDraft
        Test-Condition ($coachExitCode -eq 0) 'Real Vim split, readonly, or saving validation failed.'
        Test-Condition ([System.IO.File]::ReadAllText($draftFilePath).TrimEnd() -ceq 'Edited in Vim: 영어 UTF-8') 'Vim did not save only the edited draft in UTF-8.'
        $passedScenarioCount++
        Write-Host "PASS: $passedScenarioCount scenarios, including real Vim split/readonly/save and installed paths with spaces and Korean."
    }
    finally {
        # Restore the caller's environment and remove only this test's temporary directory.
        foreach ($name in $originalEnvironment.Keys) {
            if ($null -eq $originalEnvironment[$name]) {
                Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            }
            else {
                [System.Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], 'Process')
            }
        }
        Remove-Variable LiltSession -Scope Global -ErrorAction SilentlyContinue
        if ($previousCoachSession) { $global:LiltSession = $previousCoachSession.Value }
        $cleanupPath = [System.IO.Path]::GetFullPath($sandboxPath)
        $allowedPrefix = $script:tempDirectoryPrefix
        if ($cleanupPath.StartsWith($allowedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $cleanupPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Entry point.
Main
