#Requires -Version 7.0
param([string]$CorrectionDirectory, [string]$CodexPath)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$suggestionPath = Join-Path $CorrectionDirectory 'suggestion.md'
$responsePath = Join-Path $CorrectionDirectory 'response.md'
$logPath = Join-Path $CorrectionDirectory 'codex.log'
try {
    $codexArguments = @(
        'exec', '--model', 'gpt-6-luna'
        '-c', 'model_reasoning_effort="medium"'
        '-c', 'approval_policy="never"'
        '-c', 'web_search="disabled"'
        '--ignore-user-config', '--ephemeral', '--sandbox', 'read-only'
        '--disable', 'shell_tool', '--disable', 'plugins'
        '--disable', 'hooks', '--disable', 'apps', '--disable', 'multi_agent'
        '--disable', 'code_mode_host', '--skip-git-repo-check', '--color', 'never'
        '-C', $CorrectionDirectory, '--output-last-message', $responsePath, '-'
    )
    $request = [IO.File]::ReadAllText((Join-Path $CorrectionDirectory 'request.txt'))
    $request | & $CodexPath @codexArguments > $logPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Codex exited with code $LASTEXITCODE." }
    if (-not (Test-Path -LiteralPath $responsePath -PathType Leaf)) {
        throw 'Codex returned no suggestion.'
    }
    $response = [IO.File]::ReadAllText($responsePath)
    if ([string]::IsNullOrWhiteSpace($response)) { throw 'Codex returned no suggestion.' }
}
catch {
    $response = "Coaching unavailable: $($_.Exception.Message)`nContinue editing your original draft."
}
# Publish readiness only after the complete result (or error) has been written.
[IO.File]::WriteAllText($suggestionPath, $response, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $CorrectionDirectory 'ready'), '')
