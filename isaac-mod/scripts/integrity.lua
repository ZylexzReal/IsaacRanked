if _G._IsaacRanked_Integrity then return _G._IsaacRanked_Integrity end

local Config = include("scripts.config")
local State = include("scripts.state")
local DebugLog = include("scripts.debug_log")
local ModWhitelist = include("scripts.mod_whitelist")
local Network -- resolved lazily to avoid circular include at load time

local Integrity = {}

local consoleBlocked = false

function Integrity.readVanillaConsoleEnabled()
    local cached = _G._IsaacRanked_ConsoleCheck
    if cached and cached.known then
        return cached.enabled
    end

    local fromOptions = Config.readEnableDebugConsoleFromOptions()
    if fromOptions ~= nil then
        return fromOptions
    end

    local fromSnapshot = Config.readModConsoleSnapshot()
    if fromSnapshot ~= nil then
        return fromSnapshot
    end

    return nil
end

function Integrity.debugPreflightState(requireVerification)
    local fromOptions = Config.readEnableDebugConsoleFromOptions()
    local fromSnapshot = Config.readModConsoleSnapshot()
    local vanillaEnabled = Integrity.readVanillaConsoleEnabled()

    -- #region agent log
    DebugLog.write("H1", "integrity.lua:debugPreflightState", "preflight path and console probe", {
        runId = "debug-queue",
        requireVerification = requireVerification,
        fromOptions = fromOptions,
        fromSnapshot = fromSnapshot,
        vanillaEnabled = vanillaEnabled,
        documentsRoot = Config.getDocumentsRoot(),
        moddingRoot = Config.getModdingRoot(),
        bridgeDir = Config.getBridgeDir(),
        optionsIniPath = Config.getOptionsIniPath(),
        hasDirectorySavedata = type(Directory) == "table" and type(Directory.savedata) == "function",
        hasDirectoryModding = type(Directory) == "table" and type(Directory.modding) == "function",
        hasRepentogon = Config.hasRepentogon(),
        modPath = Config.mod and Config.mod.Path or nil,
        consoleCheckKnown = _G._IsaacRanked_ConsoleCheck and _G._IsaacRanked_ConsoleCheck.known or false,
        consoleCheckEnabled = _G._IsaacRanked_ConsoleCheck and _G._IsaacRanked_ConsoleCheck.enabled or nil,
    })
    -- #endregion

    return fromOptions, fromSnapshot, vanillaEnabled
end

function Integrity.runPreflight(requireVerification)
    if requireVerification == nil then
        requireVerification = true
    end

    local fromOptions, fromSnapshot, vanillaEnabled = Integrity.debugPreflightState(requireVerification)

    if vanillaEnabled == true then
        -- #region agent log
        DebugLog.write("H2", "integrity.lua:runPreflight", "blocked: console enabled", {
            runId = "debug-queue",
            fromOptions = fromOptions,
            fromSnapshot = fromSnapshot,
        })
        -- #endregion
        return false, "Vanilla debug console is enabled. Set EnableDebugConsole=0 in options.ini before ranked play."
    end
    if vanillaEnabled == nil and requireVerification then
        -- #region agent log
        DebugLog.write("H1", "integrity.lua:runPreflight", "blocked: could not verify console", {
            runId = "debug-queue",
            fromOptions = fromOptions,
            fromSnapshot = fromSnapshot,
            requireVerification = requireVerification,
        })
        -- #endregion
        return false, "Could not verify vanilla debug console state. Check options.ini before ranked play."
    end

    if requireVerification then
        local enabledMods, disallowedMods, modsOk = ModWhitelist.getStatus()
        if enabledMods == nil then
            -- #region agent log
            DebugLog.write("H5", "integrity.lua:runPreflight", "blocked: mod scan failed", {
                runId = "debug-queue",
                scanSource = ModWhitelist.getLastScanSource and ModWhitelist.getLastScanSource() or nil,
                hasRepentogon = Config.hasRepentogon(),
                documentsRoot = Config.getDocumentsRoot(),
                moddingRoot = Config.getModdingRoot(),
            })
            -- #endregion
            return false, "Could not scan enabled mods. Reinstall Isaac Ranked (install-mod.ps1) after your last mod change, then restart the game."
        end
        if not modsOk then
            local list = ModWhitelist.formatDisallowedList(disallowedMods)
            return false, string.format(
                "Disallowed mods enabled: %s. Ranked allows only: %s.",
                list,
                ModWhitelist.getWhitelistSummary()
            )
        end
    end

    -- #region agent log
    local enabledModCount = 0
    local modsWhitelisted = nil
    if requireVerification then
        local enabledMods, _, modsOk = ModWhitelist.getStatus()
        enabledModCount = enabledMods and #enabledMods or 0
        modsWhitelisted = modsOk
    end
    DebugLog.write("H3", "integrity.lua:runPreflight", "preflight passed", {
        runId = "debug-queue",
        vanillaEnabled = vanillaEnabled,
        requireVerification = requireVerification,
        enabledModCount = enabledModCount,
        modsWhitelisted = modsWhitelisted,
    })
    -- #endregion
    return true, nil
end

local function appendModWhitelistReport(report)
    local enabledMods, disallowedMods, modsOk = ModWhitelist.getStatus()
    report.modWhitelistVersion = ModWhitelist.VERSION
    report.modsWhitelisted = modsOk == true
    if enabledMods then
        report.enabledMods = enabledMods
    end
    if disallowedMods and #disallowedMods > 0 then
        report.disallowedMods = disallowedMods
    end
    return report
end

local function getAnticheat()
    return _G._IsaacRanked_Anticheat or include("scripts.anticheat")
end

function Integrity.beginRunProtection()
    consoleBlocked = true
    getAnticheat().beginRun()
    if MenuManager and MenuManager.IsActive and MenuManager.IsActive() and MenuManager.GetInputMask then
        Integrity._savedInputMask = MenuManager.GetInputMask()
    end
end

function Integrity.endRunProtection()
    consoleBlocked = false
    getAnticheat().endRun()
end

function Integrity.isRunProtected()
    if not consoleBlocked then
        return false
    end
    if State.current.matchState ~= State.MATCH_STATES.in_progress then
        return false
    end
    if MenuManager and MenuManager.IsActive and MenuManager.IsActive() then
        return false
    end
    return true
end

function Integrity.buildReport(matchId)
    local vanillaDisabled = Integrity.readVanillaConsoleEnabled() == false
    local report = {
        matchId = matchId,
        vanillaConsoleDisabled = vanillaDisabled,
        repentogonConsoleBlocked = consoleBlocked,
        consoleViolation = State.current.integrityViolation,
        violationReason = State.current.integrityReason,
    }

    local anticheat = getAnticheat()
    if anticheat and type(anticheat.buildReportExtras) == "function" then
        local extras = anticheat.buildReportExtras()
        if type(extras) == "table" then
            for key, value in pairs(extras) do
                report[key] = value
            end
        end
    end

    return appendModWhitelistReport(report)
end

function Integrity.flagViolation(reason)
    if State.current.integrityViolation then
        return
    end
    State.current.integrityViolation = true
    State.current.integrityReason = reason or "console_use_detected"
    State.setError("Ranked run invalidated: " .. (reason or "console use detected"))

    -- #region agent log
    Isaac.DebugString("[IsaacRanked][DBG] integrity violation: " .. tostring(reason))
    local DebugLog = _G._IsaacRanked_DebugLog
    if DebugLog then
        DebugLog.write("H2", "integrity.lua:flagViolation", "integrity violation flagged", {
            runId = "cheat-detect",
            reason = reason,
            matchState = State.current.matchState,
        })
    end
    -- #endregion

    Network = Network or _G._IsaacRanked_Network
    local matchId = State.current.matchConfig and State.current.matchConfig.matchId
    if matchId then
        Network.sendIntegrityViolation(Integrity.buildReport(matchId))
        Network.sendForfeit(matchId, reason or "integrity_violation")
    end

    State.current.matchState = State.MATCH_STATES.invalid
end

function Integrity.onExecuteCmd(cmd, params)
    return getAnticheat().onExecuteCmd(cmd, params)
end

function Integrity.onRunStarted()
    Integrity.beginRunProtection()
    getAnticheat().beginRun()
end

function Integrity.canQueue(requireVerification)
    local ok, reason = Integrity.runPreflight(requireVerification)
    if not ok then
        State.setError(reason)
        return false
    end
    return true
end

_G._IsaacRanked_Integrity = Integrity
return Integrity
