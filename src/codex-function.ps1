# Loaded from the marked block in the current PowerShell profile.
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

    # Child PowerShell processes inherit this marker and bypass the wrapper.
    if ($env:CODEX_PROMPT_COACH_ACTIVE -eq '1') {
        & $codexApplication.Source @codexArguments
        return
    }

    $previousActive = [Environment]::GetEnvironmentVariable('CODEX_PROMPT_COACH_ACTIVE', 'Process')
    $preEnabled = $null -ne (Get-Variable CodexPromptCoachSession -Scope Global -ErrorAction SilentlyContinue)
    $enablePath = Join-Path $global:CodexPromptCoachInstallRoot 'enable.ps1'
    $exitCode = 1
    try {
        if (-not $preEnabled) {
            if ($global:CodexPromptCoachConfiguredVim) {
                & $enablePath -VimPath $global:CodexPromptCoachConfiguredVim -Quiet
            }
            else {
                & $enablePath -Quiet
            }
        }
        $env:CODEX_PROMPT_COACH_ACTIVE = '1'
        & $codexApplication.Source @codexArguments
        $exitCode = $LASTEXITCODE
    }
    catch {
        Write-Error $_
    }
    finally {
        if ($null -eq $previousActive) {
            Remove-Item -LiteralPath Env:CODEX_PROMPT_COACH_ACTIVE -ErrorAction SilentlyContinue
        }
        else {
            $env:CODEX_PROMPT_COACH_ACTIVE = $previousActive
        }
        if (-not $preEnabled) { & $enablePath -Disable -Quiet }
    }
    $global:LASTEXITCODE = $exitCode
}
