# Loaded from the managed block in the PowerShell profile.
# Run registration in a temporary scope so Main does not remain in the user's profile.
& {
    function Main {
        # These values and the launcher must survive after profile loading finishes.
        $global:CodexPromptCoachInstallRoot = $PSScriptRoot
        $global:CodexPromptCoachConfiguredVim = $null

        function global:codex {
            $PSNativeCommandUseErrorActionPreference = $false
            $codexArguments = @($args)
            $codexApplication = Get-Command codex.exe -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if (-not $codexApplication) {
                Write-Error 'Codex CLI (codex.exe) was not found on PATH.'
                $global:LASTEXITCODE = 1
                return
            }
            $codexExecutablePath = $codexApplication.Source

            # Child processes inherit this marker; nested Codex calls bypass activation.
            if ($env:CODEX_PROMPT_COACH_ACTIVE -eq '1') {
                & $codexExecutablePath @codexArguments
                return
            }

            $previousActiveMarker = [Environment]::GetEnvironmentVariable('CODEX_PROMPT_COACH_ACTIVE', 'Process')
            $existingSession = Get-Variable CodexPromptCoachSession -Scope Global -ErrorAction SilentlyContinue
            $sessionAlreadyEnabled = $null -ne $existingSession
            $enableScriptPath = Join-Path $global:CodexPromptCoachInstallRoot 'enable.ps1'
            $enableParameters = @{ Quiet = $true }
            if ($global:CodexPromptCoachConfiguredVim) {
                $enableParameters.VimPath = $global:CodexPromptCoachConfiguredVim
            }
            $codexExitCode = 1

            try {
                # Activate only when the caller has not already enabled coaching manually.
                if (-not $sessionAlreadyEnabled) {
                    & $enableScriptPath @enableParameters
                }
                $env:CODEX_PROMPT_COACH_ACTIVE = '1'
                & $codexExecutablePath @codexArguments
                $codexExitCode = $LASTEXITCODE
            }
            catch {
                Write-Error $_
            }
            finally {
                # Restore the marker and only disable the session this invocation created.
                if ($null -eq $previousActiveMarker) {
                    Remove-Item -LiteralPath Env:CODEX_PROMPT_COACH_ACTIVE -ErrorAction SilentlyContinue
                }
                else {
                    $env:CODEX_PROMPT_COACH_ACTIVE = $previousActiveMarker
                }
                if (-not $sessionAlreadyEnabled) {
                    & $enableScriptPath -Disable -Quiet
                }
            }
            $global:LASTEXITCODE = $codexExitCode
        }
    }

    # Entry point: register the persistent launcher, then discard this temporary scope.
    Main
}
