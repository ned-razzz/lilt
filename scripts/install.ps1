#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$InstallPath = (Join-Path $env:USERPROFILE '.lilt'),
    [string]$VimPath,
    [string]$ProfilePath = $PROFILE,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if (-not $IsWindows) { throw 'Lilt requires Windows and PowerShell 7.' }

# In the repository this script lives in scripts/ and sources files from src/.
# After installation it lives beside those files and can update or uninstall itself.
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$sourceRoot = if (Test-Path -LiteralPath (Join-Path $repositoryRoot 'src\enable.ps1')) {
    Join-Path $repositoryRoot 'src'
} else { $PSScriptRoot }
$readmeRoot = if ($sourceRoot -ne $PSScriptRoot) { $repositoryRoot } else { $PSScriptRoot }
$readmePath = Join-Path $readmeRoot 'README.md'

$profilePath = [System.IO.Path]::GetFullPath($ProfilePath)
$profileStart = '# >>> Lilt >>>'
$profileEnd = '# <<< Lilt <<<'
$profilePattern = '(?ms)^# >>> Lilt >>>\r?\n.*?^# <<< Lilt <<<\r?\n?'
$profileText = if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
    [System.IO.File]::ReadAllText($profilePath)
} else { '' }
$profileHasBlock = $profileText -match $profilePattern

if ($Uninstall) {
    if ($profileHasBlock) {
        $profileText = [System.Text.RegularExpressions.Regex]::Replace($profileText, $profilePattern, '')
        if ([string]::IsNullOrWhiteSpace($profileText)) {
            Remove-Item -LiteralPath $profilePath -Force
        }
        else {
            [System.IO.File]::WriteAllText($profilePath, $profileText, [System.Text.UTF8Encoding]::new($true))
        }
        Write-Host 'Removed the Lilt launcher from the PowerShell profile.'
    }
    else {
        Write-Host 'The Lilt launcher is not in the PowerShell profile.'
    }
    Write-Host 'Restart PowerShell to use the updated profile.'
    return
}

# Validate in a child process so installation does not enable the current session.
$checkArgs = @('-NoLogo', '-NoProfile', '-File', (Join-Path $sourceRoot 'enable.ps1'))
if ($VimPath) { $checkArgs += @('-VimPath', $VimPath) }
& pwsh @checkArgs | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Dependency check failed. No installation files were changed.' }

$InstallPath = [System.IO.Path]::GetFullPath($InstallPath)
foreach ($relativePath in @('bin\lilt.cmd', 'bin\lilt.ps1',
        'prompts\editing-feedback-prompt.txt', 'enable.ps1', 'codex-function.ps1')) {
    $sourcePath = Join-Path $sourceRoot $relativePath
    $targetPath = Join-Path $InstallPath $relativePath
    if ([System.IO.Path]::GetFullPath($sourcePath) -eq $targetPath) { continue }
    [System.IO.Directory]::CreateDirectory((Split-Path $targetPath -Parent)) | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
}
foreach ($copy in @(
        @{ Source = $PSCommandPath; Name = 'install.ps1' },
        @{ Source = $readmePath; Name = 'README.md' }
    )) {
    $targetPath = Join-Path $InstallPath $copy.Name
    if ([System.IO.Path]::GetFullPath($copy.Source) -eq $targetPath) { continue }
    Copy-Item -LiteralPath $copy.Source -Destination $targetPath -Force
}

$separator = [Environment]::NewLine
$quotedFunctionPath = (Join-Path $InstallPath 'codex-function.ps1').Replace("'", "''")
$configuredVim = if ($VimPath) {
    "'" + (Resolve-Path -LiteralPath $VimPath).ProviderPath.Replace("'", "''") + "'"
} else { '$null' }
$profileBlock = @"
$profileStart
. '$quotedFunctionPath'
`$global:LiltConfiguredVim = $configuredVim
$profileEnd
"@
if ($profileHasBlock) {
    $profileText = [System.Text.RegularExpressions.Regex]::Replace(
        $profileText, $profilePattern, ($profileBlock + $separator))
}
else {
    $profileDirectory = Split-Path $profilePath -Parent
    [System.IO.Directory]::CreateDirectory($profileDirectory) | Out-Null
    if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
        Copy-Item -LiteralPath $profilePath -Destination ($profilePath + '.lilt.bak') -Force
    }
    if ($profileText -and -not $profileText.EndsWith("`n") -and -not $profileText.EndsWith("`r")) {
        $profileText += $separator
    }
    $profileText += $profileBlock + $separator
}
[System.IO.File]::WriteAllText($profilePath, $profileText, [System.Text.UTF8Encoding]::new($true))

Write-Host "Installed to $InstallPath"
Write-Host "Registered a Codex launcher in $profilePath. Restart PowerShell to use it."
Write-Host 'It applies the editor setting only while Codex runs in that session.'
Write-Host 'codex'
