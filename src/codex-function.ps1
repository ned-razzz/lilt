# Loaded from the managed block in the PowerShell profile.
# Run registration in a temporary scope so Main does not remain in the user's profile.
& {
    function Register-Launcher([string]$agentName) {
        # The closure keeps $agentName; the launcher must survive after profile loading finishes.
        Set-Item -Path "Function:\global:$agentName" -Value {
            $PSNativeCommandUseErrorActionPreference = $false
            $agentArguments = @($args)
            $agentApplication = Get-Command "$agentName.exe" -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if (-not $agentApplication) {
                Write-Error "$agentName CLI ($agentName.exe) was not found on PATH."
                $global:LASTEXITCODE = 1
                return
            }
            $agentExecutablePath = $agentApplication.Source

            # Child processes inherit this marker; nested agent calls bypass activation.
            if ($env:LILT_ACTIVE -eq '1') {
                & $agentExecutablePath @agentArguments
                return
            }

            $previousActiveMarker = [Environment]::GetEnvironmentVariable('LILT_ACTIVE', 'Process')
            $previousAgent = [Environment]::GetEnvironmentVariable('LILT_AGENT', 'Process')
            $existingSession = Get-Variable LiltSession -Scope Global -ErrorAction SilentlyContinue
            $sessionAlreadyEnabled = $null -ne $existingSession
            $enableScriptPath = Join-Path $global:LiltInstallRoot 'enable.ps1'
            $enableParameters = @{ Quiet = $true }
            if ($global:LiltConfiguredVim) {
                $enableParameters.VimPath = $global:LiltConfiguredVim
            }
            $agentExitCode = 1

            try {
                # Activate only when the caller has not already enabled coaching manually.
                if (-not $sessionAlreadyEnabled) {
                    & $enableScriptPath @enableParameters
                }
                $env:LILT_ACTIVE = '1'
                $env:LILT_AGENT = $agentName
                & $agentExecutablePath @agentArguments
                $agentExitCode = $LASTEXITCODE
            }
            catch {
                Write-Error $_
            }
            finally {
                # Restore the markers and only disable the session this invocation created.
                foreach ($entry in @(@('LILT_ACTIVE', $previousActiveMarker), @('LILT_AGENT', $previousAgent))) {
                    if ($null -eq $entry[1]) {
                        Remove-Item -LiteralPath "Env:$($entry[0])" -ErrorAction SilentlyContinue
                    }
                    else {
                        Set-Item -LiteralPath "Env:$($entry[0])" -Value $entry[1]
                    }
                }
                if (-not $sessionAlreadyEnabled) {
                    & $enableScriptPath -Disable -Quiet
                }
            }
            $global:LASTEXITCODE = $agentExitCode
        }.GetNewClosure()
    }

    function Main {
        $global:LiltInstallRoot = $PSScriptRoot
        $global:LiltConfiguredVim = $null
        Register-Launcher 'codex'
        Register-Launcher 'claude'
    }

    # Entry point: register the persistent launchers, then discard this temporary scope.
    Main
}
