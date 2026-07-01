#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$GameRoot,
    [string]$SaveDataPath,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"

function Write-Info([string]$Message) { Write-Host $Message -ForegroundColor Cyan }
function Write-Success([string]$Message) { Write-Host $Message -ForegroundColor Green }
function Write-Fail([string]$Message) { Write-Host $Message -ForegroundColor Red }

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

function Get-DefaultSaveDataPath {
    $candidates = @(
        (Join-Path $env:USERPROFILE "Documents\My Games\Binding of Isaac Repentance+"),
        (Join-Path $env:USERPROFILE "Documents\My Games\Binding of Isaac Repentance"),
        (Join-Path $env:USERPROFILE "OneDrive\Documents\My Games\Binding of Isaac Repentance+"),
        (Join-Path $env:USERPROFILE "OneDrive\Documents\My Games\Binding of Isaac Repentance")
    )

    if ($env:OneDrive) {
        $candidates += Join-Path $env:OneDrive "Documents\My Games\Binding of Isaac Repentance+"
    }

    foreach ($path in ($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $path) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }

    return (Join-Path $env:USERPROFILE "Documents\My Games\Binding of Isaac Repentance+")
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
        if (Test-Path -LiteralPath (Join-Path $root "isaac-ng.exe")) {
            return (Resolve-Path -LiteralPath $root).Path
        }
        if (Test-Path -LiteralPath (Join-Path $root "Repentogon\isaac-ng.exe")) {
            return (Resolve-Path -LiteralPath $root).Path
        }
    }

    throw "Could not find Isaac install folder. Pass -GameRoot <path to The Binding of Isaac Rebirth>."
}

function Ensure-WritableDirectory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    $testFile = Join-Path $Path ".isaac-ranked-write-test"
    try {
        Set-Content -LiteralPath $testFile -Value "ok" -Encoding ASCII
        Remove-Item -LiteralPath $testFile -Force
    }
    catch {
        throw "Directory is not writable: $Path"
    }
}

function Find-InstalledModDir {
    param([string]$GameRoot)

    foreach ($rel in @("mods\isaac-ranked", "Mods\isaac-ranked")) {
        $candidate = Join-Path $GameRoot $rel
        if (Test-Path -LiteralPath (Join-Path $candidate "main.lua")) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function Get-RepentogonPaths {
    param([string]$GameRoot)

    $result = @{
        SaveDataPath = $null
        ModdingDataPath = $null
    }

    if (-not $GameRoot) {
        return $result
    }

    $candidates = @(
        (Join-Path $GameRoot "Repentogon\savedatapath.txt"),
        (Join-Path $GameRoot "savedatapath.txt")
    )

    foreach ($file in $candidates) {
        if (-not (Test-Path -LiteralPath $file)) { continue }

        foreach ($line in (Get-Content -LiteralPath $file)) {
            if ($line -match '^\s*Save Data Path:\s*(.+?)\s*$') {
                $result.SaveDataPath = $Matches[1].TrimEnd('\', '/')
                continue
            }
            if ($line -match '^\s*Modding Data Path:\s*(.+?)\s*$') {
                $result.ModdingDataPath = $Matches[1].TrimEnd('\', '/')
                continue
            }
            if (-not $result.SaveDataPath -and $line -match '^[A-Za-z]:\\') {
                $result.SaveDataPath = $line.TrimEnd('\', '/')
            }
        }
    }

    return $result
}

function Write-BridgeDirConfig {
    param(
        [string]$BridgeDir,
        [string]$RepoRoot
    )

    if (-not $BridgeDir) { return }

    $serverConfig = Join-Path $RepoRoot "server\.bridge-dir"
    Write-Utf8NoBomFile -Path $serverConfig -Content ($BridgeDir.Replace('\', '/'))
}

function Write-ModDirConfig {
    param(
        [string]$ModDir,
        [string]$RepoRoot
    )

    if (-not $ModDir) { return }

    $serverConfig = Join-Path $RepoRoot "server\.mod-dir"
    Write-Utf8NoBomFile -Path $serverConfig -Content ($ModDir.Replace('\', '/'))
}

function Ensure-BridgeInboxFile {
    param([string]$ModDir)

    if (-not $ModDir) { return }

    $bridgeDir = Join-Path $ModDir "bridge"
    if (-not (Test-Path -LiteralPath $bridgeDir)) {
        New-Item -ItemType Directory -Path $bridgeDir -Force | Out-Null
    }

    $inboxFile = Join-Path $bridgeDir "inbox.lua"
    if (-not (Test-Path -LiteralPath $inboxFile)) {
        Write-Utf8NoBomFile -Path $inboxFile -Content "return [==[{}]==]`n"
    }

    $scriptsDir = Join-Path $ModDir "scripts"
    if (-not (Test-Path -LiteralPath $scriptsDir)) {
        New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
    }

    $scriptInboxFile = Join-Path $scriptsDir "bridge_inbox.lua"
    if (-not (Test-Path -LiteralPath $scriptInboxFile)) {
        $scriptInboxContent = @"
_G._IsaacRanked_InboxEnvelope = [==[{"version":0,"responses":[]}]==]
return _G._IsaacRanked_InboxEnvelope
"@
        Write-Utf8NoBomFile -Path $scriptInboxFile -Content $scriptInboxContent
    }
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
        [string]$ModdingDataPath,
        [string]$RepoRoot
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
    $moddingRoot = if ($ModdingDataPath) {
        $ModdingDataPath.TrimEnd('\', '/').Replace('\', '/')
    } else {
        ""
    }

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

    $bridgeRoot = $documentsRoot
    $bridgeDir = ($bridgeRoot.TrimEnd('/') + "/isaac-ranked-bridge").Replace('\', '/')
    Ensure-WritableDirectory -Path $bridgeDir
    if ($RepoRoot) {
        Write-BridgeDirConfig -BridgeDir $bridgeDir -RepoRoot $RepoRoot
    }

    return $bridgeDir
}

try {
    $gameRoot = Find-IsaacGameRoot -Provided $GameRoot
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
    $rgonPaths = Get-RepentogonPaths -GameRoot $gameRoot
    $saveRoot = if ($SaveDataPath) {
        $SaveDataPath
    } elseif ($rgonPaths.SaveDataPath) {
        $rgonPaths.SaveDataPath
    } else {
        Get-DefaultSaveDataPath
    }

    if (-not (Test-Path -LiteralPath $saveRoot)) {
        New-Item -ItemType Directory -Path $saveRoot -Force | Out-Null
    }

    $saveRoot = (Resolve-Path -LiteralPath $saveRoot).Path
    if (-not $saveRoot.EndsWith("\")) {
        $saveRoot += "\"
    }

    $moddingRoot = $rgonPaths.ModdingDataPath
    if (-not $moddingRoot) {
        foreach ($rel in @("mods", "Mods")) {
            $candidate = Join-Path $gameRoot $rel
            if (Test-Path -LiteralPath $candidate) {
                $moddingRoot = (Resolve-Path -LiteralPath $candidate).Path
                break
            }
        }
    }

    $modDataDir = Join-Path $saveRoot "data"
    $savedataFile = Join-Path $gameRoot "savedatapath.txt"
    $bridgeDir = Join-Path $saveRoot "isaac-ranked-bridge"

    Write-Info "Game root:       $gameRoot"
    Write-Info "Save data path:  $saveRoot"
    Write-Info "Modding path:    $moddingRoot"
    Write-Info "Bridge path:     $bridgeDir"
    Write-Info "Writing:         $savedataFile"
    Write-Host ""

    Set-Content -LiteralPath $savedataFile -Value $saveRoot -Encoding ASCII -NoNewline
    Add-Content -LiteralPath $savedataFile -Value "" -Encoding ASCII

    Ensure-WritableDirectory -Path $saveRoot
    Ensure-WritableDirectory -Path $modDataDir
    Ensure-WritableDirectory -Path $bridgeDir
    Write-BridgeDirConfig -BridgeDir $bridgeDir -RepoRoot $repoRoot

    foreach ($rel in @("mods\isaac-ranked-bridge", "Mods\isaac-ranked-bridge")) {
        $legacyBridgeMod = Join-Path $gameRoot $rel
        if (Test-Path -LiteralPath $legacyBridgeMod) {
            Remove-Item -LiteralPath $legacyBridgeMod -Recurse -Force
            Write-Info "Removed legacy bridge mod folder: $legacyBridgeMod"
        }
    }

    $modDir = Find-InstalledModDir -GameRoot $gameRoot
    if ($modDir) {
        Write-ModConsoleSnapshot -DestinationDir $modDir -SaveDataPath $saveRoot -ModdingDataPath $moddingRoot -RepoRoot $repoRoot | Out-Null
        Write-ModDirConfig -ModDir $modDir -RepoRoot $repoRoot
        Ensure-BridgeInboxFile -ModDir $modDir
        Write-Info "Updated mod paths and console snapshot in $modDir"
    }
    else {
        Write-Host "Warning: isaac-ranked mod not found under $gameRoot; skipped mod path snapshot." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Success "Isaac save/mod data paths fixed."
    Write-Host "Restart Isaac and the matchmaking server after this change."
    Write-Host ""
    Write-Host "Created/verified:"
    Write-Host "  $savedataFile"
    Write-Host "  $modDataDir"
    Write-Host "  $bridgeDir"
    Write-Host "  $(Join-Path $repoRoot 'server\.bridge-dir')"
    Write-Host ""
    Wait-ForKeyIfNeeded
    exit 0
}
catch {
    Write-Host ""
    Write-Fail $_.Exception.Message
    Write-Host ""
    Write-Host "Manual fix:"
    Write-Host "  1. Create savedatapath.txt in your Isaac install folder"
    Write-Host "  2. Put this single line inside it:"
    Write-Host "     C:\Users\<you>\Documents\My Games\Binding of Isaac Repentance+\"
    Write-Host "  3. Create the folder above if it does not exist"
    Write-Host ""
    Wait-ForKeyIfNeeded
    exit 1
}
