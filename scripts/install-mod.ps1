#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ModsPath,
    [string]$RepoRoot,
    [string]$ModFolderName = "isaac-ranked",
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"

function Write-Info([string]$Message) {
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Success([string]$Message) {
    Write-Host $Message -ForegroundColor Green
}

function Write-Fail([string]$Message) {
    Write-Host $Message -ForegroundColor Red
}

function Write-Utf8NoBomFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Wait-ForKeyIfNeeded() {
    if (-not $NoPause -and [Environment]::UserInteractive) {
        Write-Host ""
        Write-Host "Press Enter to close..." -ForegroundColor DarkGray
        [void](Read-Host)
    }
}

function Get-RepoRoot {
    param([string]$Provided)

    if ($Provided) {
        return (Resolve-Path -LiteralPath $Provided).Path
    }

    $fromScript = Join-Path $PSScriptRoot ".."
    if (Test-Path -LiteralPath (Join-Path $fromScript "isaac-mod\main.lua")) {
        return (Resolve-Path -LiteralPath $fromScript).Path
    }

    $fromCwd = Get-Location
    if (Test-Path -LiteralPath (Join-Path $fromCwd "isaac-mod\main.lua")) {
        return (Resolve-Path -LiteralPath $fromCwd).Path
    }

    throw "Could not find repo root. Run from the IsaacRanked folder or pass -RepoRoot <path>."
}

function Get-IsaacDataRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $candidates = @(
        (Join-Path $env:USERPROFILE "Documents\My Games"),
        (Join-Path $env:USERPROFILE "OneDrive\Documents\My Games"),
        (Join-Path $env:USERPROFILE "OneDrive - Personal\Documents\My Games")
    )

    if ($env:OneDrive) {
        $candidates += Join-Path $env:OneDrive "Documents\My Games"
    }

    foreach ($base in ($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $base)) { continue }

        foreach ($game in @(
            "Binding of Isaac Repentance+",
            "Binding of Isaac Repentance",
            "Binding of Isaac Afterbirth+"
        )) {
            $full = Join-Path $base $game
            if (Test-Path -LiteralPath $full) {
                $roots.Add($full)
            }
        }
    }

    return $roots
}

function Find-IsaacGameRoot {
    param([string]$Provided)

    if ($Provided) {
        return (Resolve-Path -LiteralPath $Provided).Path
    }

    $steamRoots = @(
        "D:\SteamLibrary\steamapps\common\The Binding of Isaac Rebirth",
        "D:\steamLibrary\steamapps\common\The Binding of Isaac Rebirth",
        "C:\Program Files (x86)\Steam\steamapps\common\The Binding of Isaac Rebirth",
        "E:\SteamLibrary\steamapps\common\The Binding of Isaac Rebirth"
    )

    foreach ($root in $steamRoots) {
        if (Test-Path -LiteralPath (Join-Path $root "Mods")) {
            return (Resolve-Path -LiteralPath $root).Path
        }
        if (Test-Path -LiteralPath (Join-Path $root "isaac-ng.exe")) {
            return (Resolve-Path -LiteralPath $root).Path
        }
        if (Test-Path -LiteralPath (Join-Path $root "Repentogon\isaac-ng.exe")) {
            return (Resolve-Path -LiteralPath $root).Path
        }
    }

    return $null
}

function Get-DefaultModsPath {
    $gameRoot = Find-IsaacGameRoot
    if ($gameRoot) {
        $modsDir = Join-Path $gameRoot "Mods"
        if (-not (Test-Path -LiteralPath $modsDir)) {
            $modsDir = Join-Path $gameRoot "mods"
        }
        return (Join-Path $modsDir $ModFolderName)
    }

    # Fallback for unusual setups only.
    $roots = Get-IsaacDataRoots
    if ($roots.Count -eq 0) {
        throw @"
Could not find Isaac install folder or save folder.
Pass -ModsPath explicitly, for example:
  -ModsPath "D:\SteamLibrary\steamapps\common\The Binding of Isaac Rebirth\Mods\isaac-ranked"
"@
    }

    $preferred = $roots | Where-Object { $_.EndsWith("Binding of Isaac Repentance+") } | Select-Object -First 1
    if (-not $preferred) { $preferred = $roots[0] }

    return (Join-Path $preferred "mods\$ModFolderName")
}

function Install-ModFiles {
    param(
        [string]$SourceDir,
        [string]$DestinationDir
    )

    $requiredFiles = @(
        "main.lua",
        "metadata.xml",
        "scripts\config.lua",
        "scripts\match.lua",
        "scripts\network.lua"
    )

    if (-not (Test-Path -LiteralPath $SourceDir)) {
        throw "Mod source not found: $SourceDir"
    }

  foreach ($rel in $requiredFiles) {
        $path = Join-Path $SourceDir $rel
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Mod source is incomplete. Missing: $rel"
        }
    }

    if (Test-Path -LiteralPath $DestinationDir) {
        Write-Info "Removing previous install at $DestinationDir"
        Remove-Item -LiteralPath $DestinationDir -Recurse -Force
    }

    $parent = Split-Path -Parent $DestinationDir
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    # Robocopy is more reliable than Copy-Item on Windows paths with spaces.
    $robocopy = Get-Command robocopy -ErrorAction SilentlyContinue
    if ($robocopy) {
        & robocopy $SourceDir $DestinationDir /E /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "Robocopy failed with exit code $LASTEXITCODE"
        }
    }
    else {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
        Copy-Item -Path (Join-Path $SourceDir "*") -Destination $DestinationDir -Recurse -Force
    }

    foreach ($rel in $requiredFiles) {
        $installed = Join-Path $DestinationDir $rel
        if (-not (Test-Path -LiteralPath $installed)) {
            throw "Install verification failed. Missing: $installed"
        }
    }
}

function Write-InstalledPathsFile {
    param(
        [string]$DestinationDir,
        [string]$SaveDataPath,
        [string]$ModdingDataPath = ""
    )

    $documentsRoot = $SaveDataPath.TrimEnd('\', '/').Replace('\', '/')
    $moddingRoot = if ($ModdingDataPath) { $ModdingDataPath.TrimEnd('\', '/').Replace('\', '/') } else { "" }
    $pathsFile = Join-Path $DestinationDir "scripts\paths.lua"
    $content = @"
return {
    documentsRoot = "$documentsRoot",
    moddingRoot = "$moddingRoot",
    bridgeSubdir = "isaac-ranked-bridge",
}
"@

    Write-Utf8NoBomFile -Path $pathsFile -Content $content
    Write-ModConsoleSnapshot -DestinationDir $DestinationDir -SaveDataPath $SaveDataPath -ModdingDataPath $ModdingDataPath
}

function Get-EnableDebugConsoleFromOptions {
    param([string]$SaveDataPath)

    $optionsIni = Join-Path $SaveDataPath "options.ini"
    if (-not (Test-Path -LiteralPath $optionsIni)) {
        return $null
    }

    $match = Select-String -Path $optionsIni -Pattern '^\s*EnableDebugConsole\s*=\s*(\d+)\s*$' | Select-Object -First 1
    if (-not $match) {
        return $null
    }

    return ($match.Matches[0].Groups[1].Value -eq "1")
}

function Get-EnabledModFoldersFromLog {
    param([string]$LogPath)

    if (-not (Test-Path -LiteralPath $LogPath)) {
        return @()
    }

    $content = Get-Content -LiteralPath $LogPath -Raw
    $lastStart = $content.LastIndexOf("Enabled Mods START")
    if ($lastStart -lt 0) {
        return @()
    }

    $blockStart = $content.IndexOf([char]10, $lastStart)
    if ($blockStart -lt 0) {
        return @()
    }
    $blockStart++

    $blockEnd = $content.IndexOf("Enabled Mods END", $blockStart)
    if ($blockEnd -lt 0) {
        return @()
    }

    $block = $content.Substring($blockStart, $blockEnd - $blockStart)
    $mods = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($block -split "`r?`n")) {
        $folder = $line.Trim()
        if ($folder -and $folder -notmatch 'Enabled Mods' -and $folder -notmatch '^\[INFO\]') {
            $mods.Add($folder)
        }
    }

    return $mods | Sort-Object -Unique
}

function Write-EnabledModsSnapshot {
    param(
        [string]$DestinationDir,
        [string]$SaveDataPath
    )

    $logPath = Join-Path $SaveDataPath "log.txt"
    $mods = Get-EnabledModFoldersFromLog -LogPath $logPath
    $scriptsDir = Join-Path $DestinationDir "scripts"
    if (-not (Test-Path -LiteralPath $scriptsDir)) {
        New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
    }

    $escapedMods = ($mods | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ",`n        "
    if (-not $escapedMods) {
        $escapedMods = ""
    }

    $content = @"
return {
    enabledMods = {
        $escapedMods
    },
    capturedAt = "install",
}
"@

    Write-Utf8NoBomFile -Path (Join-Path $scriptsDir "enabled_mods_preflight.lua") -Content $content
    if ($mods.Count -gt 0) {
        Write-Info "Wrote enabled_mods_preflight.lua ($($mods.Count) mods from log.txt)"
    }
    else {
        Write-Info "No enabled mods block in log.txt; wrote empty enabled_mods_preflight.lua"
    }
}

function Write-ModConsoleSnapshot {
    param(
        [string]$DestinationDir,
        [string]$SaveDataPath,
        [string]$ModdingDataPath = ""
    )

    $consoleEnabled = Get-EnableDebugConsoleFromOptions -SaveDataPath $SaveDataPath
    if ($null -eq $consoleEnabled) {
        $consoleEnabled = $false
    }

    $flag = if ($consoleEnabled) { "1" } else { "0" }
    $scriptsDir = Join-Path $DestinationDir "scripts"
    if (-not (Test-Path -LiteralPath $scriptsDir)) {
        New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
    }

    Set-Content -LiteralPath (Join-Path $scriptsDir "console_state.txt") -Value $flag -Encoding ASCII -NoNewline

    $documentsRoot = $SaveDataPath.TrimEnd('\', '/').Replace('\', '/')
    $moddingRoot = if ($ModdingDataPath) { $ModdingDataPath.TrimEnd('\', '/').Replace('\', '/') } else { "" }
    $pathsFile = Join-Path $scriptsDir "paths.lua"
    $pathsContent = @"
return {
    documentsRoot = "$documentsRoot",
    moddingRoot = "$moddingRoot",
    bridgeSubdir = "isaac-ranked-bridge",
}
"@
    Write-Utf8NoBomFile -Path $pathsFile -Content $pathsContent

    $preflight = @"
return {
    vanillaConsoleEnabled = $($consoleEnabled.ToString().ToLower()),
}
"@
    Write-Utf8NoBomFile -Path (Join-Path $scriptsDir "preflight.lua") -Content $preflight
    Write-EnabledModsSnapshot -DestinationDir $DestinationDir -SaveDataPath $SaveDataPath
}

function Get-DefaultSaveDataPathForInstall {
    $candidates = @(
        (Join-Path $env:USERPROFILE "Documents\My Games\Binding of Isaac Repentance+"),
        (Join-Path $env:USERPROFILE "Documents\My Games\Binding of Isaac Repentance")
    )

    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }

    return $candidates[0]
}

try {
    $repo = Get-RepoRoot -Provided $RepoRoot
    $source = Join-Path $repo "isaac-mod"
    $destination = if ($ModsPath) { $ModsPath } else { Get-DefaultModsPath }

    Write-Info "Repo:        $repo"
    Write-Info "Source:      $source"
    Write-Info "Destination: $destination"
    Write-Host ""

    Install-ModFiles -SourceDir $source -DestinationDir $destination

    $fixScript = Join-Path $PSScriptRoot "fix-isaac-paths.ps1"
    if (Test-Path -LiteralPath $fixScript) {
        Write-Info "Fixing Isaac save/mod data paths..."
        & $fixScript -NoPause
        Write-Host ""
    }
    else {
        $gameRoot = Find-IsaacGameRoot
        $saveDataPath = Get-DefaultSaveDataPathForInstall
        Write-InstalledPathsFile -DestinationDir $destination -SaveDataPath $saveDataPath
        Write-Info "Wrote paths.lua for $saveDataPath"
    }

    Write-Host ""
    Write-Success "Installed Isaac Ranked mod successfully."
    Write-Host "Enable it in Isaac: Mods menu -> Isaac Ranked -> restart if prompted."
    Write-Host ""
    Wait-ForKeyIfNeeded
    exit 0
}
catch {
    Write-Host ""
    Write-Fail "Install failed: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "Try running:"
    Write-Host "  powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Write-Host ""
    Wait-ForKeyIfNeeded
    exit 1
}
