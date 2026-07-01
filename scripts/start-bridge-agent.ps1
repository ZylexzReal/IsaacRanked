#Requires -Version 5.1
# Developer-only: forwards local log bridge to a remote VPS when Repentogon HTTP is unavailable.
# Steam Workshop players should NOT need this script.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RemoteBridgeUrl,
    [string]$RepoRoot,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    param([string]$Provided)

    if ($Provided) {
        return (Resolve-Path -LiteralPath $Provided).Path
    }

    $fromScript = Join-Path $PSScriptRoot ".."
    if (Test-Path -LiteralPath (Join-Path $fromScript "server\package.json")) {
        return (Resolve-Path -LiteralPath $fromScript).Path
    }

    throw "Could not find IsaacRanked repo root."
}

function Write-Utf8NoBomFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

$root = Get-RepoRoot -Provided $RepoRoot
$serverDir = Join-Path $root "server"
$agentUrlFile = Join-Path $serverDir ".agent-url"

if (-not (Test-Path -LiteralPath $serverDir)) {
    throw "Server directory not found: $serverDir"
}

$normalizedUrl = $RemoteBridgeUrl.Trim().TrimEnd("/")
if (-not $normalizedUrl.EndsWith("/bridge")) {
    $normalizedUrl = "$normalizedUrl/bridge"
}

Write-Utf8NoBomFile -Path $agentUrlFile -Content "$normalizedUrl`n"
Write-Host "Saved remote bridge URL to $agentUrlFile" -ForegroundColor Green
Write-Host "Starting bridge agent (Ctrl+C to stop)..." -ForegroundColor Cyan

$env:ISAAC_RANKED_REMOTE_BRIDGE_URL = $normalizedUrl

Push-Location $serverDir
try {
    npm run agent
} finally {
    Pop-Location
    if (-not $NoPause -and [Environment]::UserInteractive) {
        Write-Host ""
        Write-Host "Press Enter to close..." -ForegroundColor DarkGray
        [void](Read-Host)
    }
}
