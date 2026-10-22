#Requires -Version 7.0
param([string]$CorrectionDirectory, [string]$AgentPath, [ValidateSet('codex', 'claude')][string]$Agent = 'codex')

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$suggestionPath = Join-Path $CorrectionDirectory 'suggestion.md'
$responsePath = Join-Path $CorrectionDirectory 'response.md'
$logPath = Join-Path $CorrectionDirectory 'agent.log'
try {
    $request = [IO.File]::ReadAllText((Join-Path $CorrectionDirectory 'request.txt'))
    if ($Agent -eq 'claude') {
        # Print mode with no tools, settings, MCP servers, or saved session; stdout is the suggestion.
        $agentArguments = @(
            '-p', '--model', 'sonnet', '--effort', 'medium', '--no-session-persistence'
            '--tools', '', '--disable-slash-commands', '--strict-mcp-config'
            '--setting-sources', ''
            '--system-prompt', 'You are an English writing coach. Reply with text only.'
        )
        Push-Location -LiteralPath $CorrectionDirectory
        try { $request | & $AgentPath @agentArguments > $responsePath 2> $logPath }
        finally { Pop-Location }
    }
    else {
        $agentArguments = @(
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
        $request | & $AgentPath @agentArguments > $logPath 2>&1
    }
    if ($LASTEXITCODE -ne 0) { throw "$Agent exited with code $LASTEXITCODE." }
    if (-not (Test-Path -LiteralPath $responsePath -PathType Leaf)) {
        throw "$Agent returned no suggestion."
    }
    $response = [IO.File]::ReadAllText($responsePath)
    if ([string]::IsNullOrWhiteSpace($response)) { throw "$Agent returned no suggestion." }
}
catch {
    $response = "Coaching unavailable: $($_.Exception.Message)`nContinue editing your original draft."
}
# Publish readiness only after the complete result (or error) has been written.
[IO.File]::WriteAllText($suggestionPath, $response, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $CorrectionDirectory 'ready'), '')
