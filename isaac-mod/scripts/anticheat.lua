if _G._IsaacRanked_Anticheat then return _G._IsaacRanked_Anticheat end

local State = include("scripts.state")

local Anticheat = {}

Anticheat.VERSION = 1

-- Inventory anticheat authorizes pickups touched by the player (shops, devil deals,
-- beggar drops, planetarium/treasure pedestals, crane/arcade prizes, etc.) via
-- MC_PRE_PICKUP_COLLISION + MC_POST_ADD_COLLECTIBLE. Pool rolls (MC_POST_GET_COLLECTIBLE
-- on room spawn) are ignored. Console giveitem has no pickup collision and is caught
-- by inventory audit.
local BLOCKED_COMMANDS = {
    giveitem = true,
    give = true,
    spawn = true,
    debug = true,
    stage = true,
    room = true,
    ["goto"] = true,
    restart = true,
    reseed = true,
    gold = true,
    bombs = true,
    keys = true,
    redraw = true,
    reload = true,
    lua = true,
    export = true,
    import = true,
    macro = true,
    gridspawn = true,
    entity = true,
    item = true,
    trinket = true,
    card = true,
    pill = true,
    challenge = true,
}

local active = false
local lastCommandHistorySize = 0
local lastConsoleHistorySize = 0
local lastAuditFrame = 0
local startingCollectibles = {}
local authorizedCollectibles = {}
local pendingPickupAuth = {}
local pendingAnyPickupAuth = 0
local consoleActivityUntilFrame = 0
local Integrity

local function getIntegrity()
    Integrity = Integrity or _G._IsaacRanked_Integrity or include("scripts.integrity")
    return Integrity
end

local function isProtected()
    local integrity = getIntegrity()
    return active and integrity and integrity.isRunProtected()
end

local function normalizeCommand(line)
    if type(line) ~= "string" then
        return ""
    end
    return line:lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function isBlockedCommand(line)
    local normalized = normalizeCommand(line)
    if normalized == "" then
        return false
    end

    local firstWord = normalized:match("^([%w_]+)")
    if not firstWord then
        return false
    end

    if BLOCKED_COMMANDS[firstWord] then
        return true
    end

    if firstWord == "g" or firstWord == "c" or firstWord == "p" then
        return #normalized > #firstWord
    end

    return false
end

local function markConsoleActivity(extraFrames)
    local game = Game and Game()
    if not game then
        return
    end
    local frame = game:GetFrameCount()
    consoleActivityUntilFrame = math.max(consoleActivityUntilFrame, frame + (extraFrames or 90))
end

local function callImGuiIsVisible()
    if not ImGui or type(ImGui.IsVisible) ~= "function" then
        return false
    end
    local ok, visible = pcall(function()
        return ImGui:IsVisible()
    end)
    if not ok then
        ok, visible = pcall(ImGui.IsVisible, ImGui)
    end
    return ok and visible == true
end

local function imguiElementActive(elementId)
    if type(ImGui.GetVisible) == "function" then
        local ok, visible = pcall(function()
            return ImGui:GetVisible(elementId)
        end)
        if not ok then
            ok, visible = pcall(ImGui.GetVisible, ImGui, elementId)
        end
        if ok and visible then
            return true
        end
    end
    if type(ImGui.GetWindowPinned) == "function" then
        local ok, pinned = pcall(function()
            return ImGui:GetWindowPinned(elementId)
        end)
        if not ok then
            ok, pinned = pcall(ImGui.GetWindowPinned, ImGui, elementId)
        end
        if ok and pinned then
            return true
        end
    end
    return false
end

local function isConsoleActive()
    local game = Game and Game()
    if not game then
        return false
    end
    if game:GetFrameCount() <= consoleActivityUntilFrame then
        return true
    end
    if ImGui then
        if callImGuiIsVisible() then
            return true
        end
        for _, elementId in ipairs({ "console", "Console", "DebugConsole", "debugconsole", "imguidebug" }) do
            if imguiElementActive(elementId) then
                return true
            end
        end
    end
    return false
end

local function authorizeCollectible(collectibleType)
    authorizedCollectibles[collectibleType] = (authorizedCollectibles[collectibleType] or 0) + 1
end

local function consumePendingAuth(collectibleType)
    local pickupPending = pendingPickupAuth[collectibleType] or 0
    if pickupPending > 0 then
        pendingPickupAuth[collectibleType] = pickupPending - 1
        authorizeCollectible(collectibleType)
        return true
    end

    if pendingAnyPickupAuth > 0 then
        pendingAnyPickupAuth = pendingAnyPickupAuth - 1
        authorizeCollectible(collectibleType)
        return true
    end

    return false
end

local function isRankedPlayer(player)
    if not player then
        return true
    end
    local main = Game():GetPlayer(0)
    if not main then
        return true
    end
    return player.InitSeed == main.InitSeed
end

local function flag(reason)
    local integrity = getIntegrity()
    if integrity then
        integrity.flagViolation(reason)
    end
end

local function snapshotPlayerCollectibles(player)
    local counts = {}
    if not player then
        return counts
    end

    local maxSlots = player.GetMaxCollectibles and player:GetMaxCollectibles() or 0
    for slot = 0, maxSlots - 1 do
        local collectibleType = player:GetCollectible(slot)
        if collectibleType and collectibleType > 0 then
            counts[collectibleType] = (counts[collectibleType] or 0) + 1
        end
    end

    return counts
end

local function mergeCounts(target, source)
    for collectibleType, count in pairs(source) do
        target[collectibleType] = (target[collectibleType] or 0) + count
    end
end

local function countCollectibles(counts)
    local total = 0
    for _, count in pairs(counts) do
        total = total + count
    end
    return total
end

function Anticheat.beginRun()
    active = true
    lastCommandHistorySize = 0
    lastConsoleHistorySize = 0
    lastAuditFrame = 0
    startingCollectibles = {}
    authorizedCollectibles = {}
    pendingPickupAuth = {}
    pendingAnyPickupAuth = 0
    consoleActivityUntilFrame = 0

    if Console then
        if type(Console.GetCommandHistory) == "function" then
            local history = Console.GetCommandHistory()
            if type(history) == "table" then
                lastCommandHistorySize = #history
            end
        end
        if type(Console.GetHistory) == "function" then
            local history = Console.GetHistory()
            if type(history) == "table" then
                lastConsoleHistorySize = #history
            end
        end
    end

    local game = Game and Game()
    if game then
        local player = game:GetPlayer(0)
        startingCollectibles = snapshotPlayerCollectibles(player)
        authorizedCollectibles = {}
        mergeCounts(authorizedCollectibles, startingCollectibles)
    end
end

function Anticheat.endRun()
    active = false
    lastCommandHistorySize = 0
    lastConsoleHistorySize = 0
    lastAuditFrame = 0
    startingCollectibles = {}
    authorizedCollectibles = {}
    pendingPickupAuth = {}
    pendingAnyPickupAuth = 0
    consoleActivityUntilFrame = 0
end

local function pollConsoleToggleKey()
    if not isProtected() then
        return
    end
    if not Keyboard or not Keyboard.KEY_GRAVE_ACCENT or not Input or not Input.IsButtonTriggered then
        return
    end

    for controller = 0, 7 do
        if Input.IsButtonTriggered(Keyboard.KEY_GRAVE_ACCENT, controller) then
            markConsoleActivity(120)
            -- #region agent log
            Isaac.DebugString("[IsaacRanked][DBG] grave key pressed during ranked run")
            local DebugLog = _G._IsaacRanked_DebugLog
            if DebugLog then
                DebugLog.write("H3", "anticheat.lua:pollConsoleToggleKey", "console toggle key", {
                    runId = "console-fix",
                    controller = controller,
                })
            end
            -- #endregion
            flag("debug console opened during ranked run")
            return
        end
    end
end

function Anticheat.pollConsoleToggleKey()
    pollConsoleToggleKey()
end

function Anticheat.suppressConsole()
    if not isProtected() then
        return
    end

    if MenuManager and MenuManager.IsActive and MenuManager.IsActive() then
        return
    end

    if isConsoleActive() then
        markConsoleActivity(90)
        -- #region agent log
        Isaac.DebugString("[IsaacRanked][DBG] console active detected in suppressConsole")
        local DebugLog = _G._IsaacRanked_DebugLog
        if DebugLog then
            DebugLog.write("H1", "anticheat.lua:suppressConsole", "console visible", {
                runId = "console-fix",
                imguiVisible = callImGuiIsVisible(),
            })
        end
        -- #endregion
        flag("debug console opened during ranked run")
        return
    end

    if ImGui and type(ImGui.Hide) == "function" then
        ImGui.Hide()
    end
end

function Anticheat.pollCommandHistory()
    if not isProtected() then
        return
    end
    if not Console then
        return
    end

    if type(Console.GetCommandHistory) == "function" then
        local history = Console.GetCommandHistory()
        if type(history) == "table" then
            for index = lastCommandHistorySize + 1, #history do
                local line = history[index]
                if isBlockedCommand(line) then
                    markConsoleActivity(120)
                    flag("blocked console command: " .. tostring(line))
                    return
                end
            end
            lastCommandHistorySize = #history
        end
    end

    if type(Console.GetHistory) == "function" then
        local consoleHistory = Console.GetHistory()
        if type(consoleHistory) == "table" then
            for index = lastConsoleHistorySize + 1, #consoleHistory do
                local line = consoleHistory[index]
                if isBlockedCommand(line) then
                    markConsoleActivity(120)
                    flag("blocked console command: " .. tostring(line))
                    return
                end
            end
            lastConsoleHistorySize = #consoleHistory
        end
    end
end

function Anticheat.onPreGetCollectible(collectibleType)
    -- MC_PRE_GET_COLLECTIBLE fires for item pool rolls (treasure room pedestals, etc.),
    -- not player pickups. Do not authorize here.
end

function Anticheat.onPrePickupCollision(pickup, collider)
    if not isProtected() or isConsoleActive() then
        return
    end
    if not pickup or not collider then
        return
    end
    local player = collider.ToPlayer and collider:ToPlayer()
    if not player or not isRankedPlayer(player) then
        return
    end
    if pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE then
        pendingAnyPickupAuth = pendingAnyPickupAuth + 1
        local collectibleType = pickup.SubType
        if collectibleType and collectibleType > 0 then
            pendingPickupAuth[collectibleType] = (pendingPickupAuth[collectibleType] or 0) + 1
        end
        -- #region agent log
        local DebugLog = _G._IsaacRanked_DebugLog
        if DebugLog then
            DebugLog.write("H5", "anticheat.lua:onPrePickupCollision", "pickup authorized", {
                runId = "collectible-fix",
                collectibleType = collectibleType,
                pendingTyped = collectibleType and pendingPickupAuth[collectibleType] or 0,
                pendingAny = pendingAnyPickupAuth,
            })
        end
        -- #endregion
    end
end

function Anticheat.onPostGetCollectible(collectibleType)
    -- Pool roll only (treasure/planetarium pedestal spawn, etc.). Not a player pickup.
end

function Anticheat.onPostAddCollectible(collectibleType, charge, firstTime, slot, varData, player)
    if not isProtected() then
        return
    end
    if not firstTime or not collectibleType or collectibleType <= 0 then
        return
    end
    if not isRankedPlayer(player) then
        return
    end

    if consumePendingAuth(collectibleType) then
        return
    end

    -- Legit sources (shop purchase, beggar drop, crane prize, etc.) should have set
    -- pending auth via PRE_PICKUP_COLLISION. Console giveitem does not; audit catches it.
end

local function reconcilePendingInventoryAuths(counts)
    for collectibleType, count in pairs(counts) do
        local allowed = authorizedCollectibles[collectibleType] or 0
        while count > allowed do
            if consumePendingAuth(collectibleType) then
                allowed = allowed + 1
            else
                break
            end
        end
    end
end

function Anticheat.auditInventory()
    if not isProtected() then
        return
    end

    local game = Game and Game()
    if not game then
        return
    end

    local player = game:GetPlayer(0)
    if not player then
        return
    end

    local current = snapshotPlayerCollectibles(player)
    reconcilePendingInventoryAuths(current)
    for collectibleType, count in pairs(current) do
        local allowed = authorizedCollectibles[collectibleType] or 0
        if count > allowed then
            -- #region agent log
            Isaac.DebugString("[IsaacRanked][DBG] auditInventory unauthorized type="
                .. tostring(collectibleType) .. " count=" .. tostring(count) .. " allowed=" .. tostring(allowed))
            local DebugLog = _G._IsaacRanked_DebugLog
            if DebugLog then
                DebugLog.write("H5", "anticheat.lua:auditInventory", "unauthorized inventory increase", {
                    runId = "collectible-fix",
                    collectibleType = collectibleType,
                    count = count,
                    allowed = allowed,
                    pendingPickup = pendingPickupAuth[collectibleType] or 0,
                    pendingAny = pendingAnyPickupAuth,
                })
            end
            -- #endregion
            flag("unauthorized collectible: " .. tostring(collectibleType))
            return
        end
    end
end

function Anticheat.onInputAction(entity, hook, action)
    if not isProtected() then
        return
    end

    if callImGuiIsVisible() then
        -- #region agent log
        Isaac.DebugString("[IsaacRanked][DBG] ImGui visible during ranked run (input action)")
        local DebugLog = _G._IsaacRanked_DebugLog
        if DebugLog then
            DebugLog.write("H1", "anticheat.lua:onInputAction", "imgui visible", {
                runId = "console-fix-2",
                hook = hook,
                action = action,
            })
        end
        -- #endregion
        flag("debug console opened during ranked run")
        return false
    end

    if hook ~= InputHook.IS_ACTION_TRIGGERED then
        return
    end

    if Keyboard and action == Keyboard.KEY_GRAVE_ACCENT then
        -- #region agent log
        Isaac.DebugString("[IsaacRanked][DBG] grave key intercepted via MC_INPUT_ACTION")
        local DebugLog = _G._IsaacRanked_DebugLog
        if DebugLog then
            DebugLog.write("H3", "anticheat.lua:onInputAction", "grave key blocked", {
                runId = "console-fix-2",
                action = action,
            })
        end
        -- #endregion
        flag("debug console opened during ranked run")
        return false
    end
end

function Anticheat.pollConsoleVisibility()
    if not isProtected() then
        return
    end
    if callImGuiIsVisible() then
        -- #region agent log
        Isaac.DebugString("[IsaacRanked][DBG] ImGui visible during ranked run (post render)")
        -- #endregion
        flag("debug console opened during ranked run")
    end
end

function Anticheat.onExecuteCmd(cmd)
    if not isProtected() then
        return nil
    end

    local command = normalizeCommand(cmd)
    if command == "" then
        return nil
    end

    if isBlockedCommand(command) then
        flag("console command blocked: " .. tostring(cmd))
        return "Isaac Ranked: console commands are disabled during ranked runs."
    end

    flag("console command blocked: " .. tostring(cmd))
    return "Isaac Ranked: console commands are disabled during ranked runs."
end

local loggedAnticheatTick = false

function Anticheat.tick()
    if not isProtected() then
        return
    end

    Anticheat.pollConsoleToggleKey()
    Anticheat.suppressConsole()
    Anticheat.pollCommandHistory()

    -- #region agent log
    if not loggedAnticheatTick then
        loggedAnticheatTick = true
        Isaac.DebugString("[IsaacRanked][DBG] anticheat tick ok protected=true")
        local DebugLog = _G._IsaacRanked_DebugLog
        if DebugLog then
            DebugLog.write("H1", "anticheat.lua:tick", "anticheat tick running", {
                runId = "post-fix",
                matchState = State.current.matchState,
            })
        end
    end
    -- #endregion

    local frame = Game():GetFrameCount()
    if frame - lastAuditFrame >= 5 then
        lastAuditFrame = frame
        Anticheat.auditInventory()
    end
end

function Anticheat.buildReportExtras()
    return {
        anticheatVersion = Anticheat.VERSION,
        inventoryTracked = countCollectibles(authorizedCollectibles),
        startingCollectibleCount = countCollectibles(startingCollectibles),
    }
end

_G._IsaacRanked_Anticheat = Anticheat
return Anticheat
