if _G._IsaacRanked_Menu then return _G._IsaacRanked_Menu end

local Config = include("scripts.config")
local State = include("scripts.state")
local Integrity = include("scripts.integrity")
local Network = include("scripts.network")
local Match = include("scripts.match")

local Menu = {}

local MENU_LAYOUT = MainMenuType.GAME

-- Preconfigured keybind to open ranked menu on main menu.
-- Change to another Keyboard.KEY_* value if desired.
Menu.OPEN_KEY = Keyboard.KEY_F6

Menu.RANKED_SCREEN_POS = Vector(168, 78)
Menu.RANKED_SCREEN_LINE = 13
Menu.HINT_POS = Vector(168, 208)

Menu.rankedScreenOpen = false
Menu.previousMenu = MENU_LAYOUT
Menu.savedInputMask = nil
Menu.selectedAction = 1
local loggedMenuActionCount = 0
local MAX_MENU_ACTION_LOGS = 40
local loggedMenuCallbackCount = 0
local MAX_MENU_CALLBACK_LOGS = 30
local menuRenderFrame = 0
local lastInputFrameProcessed = -1
local confirmCooldownUntilFrame = -1

local actions = { "Queue Ranked", "Cancel Queue", "Mock Match", "Reconnect" }

local menuFont = nil
local COLOR_WHITE = KColor(1, 1, 1, 1)
local COLOR_DIM = KColor(0.55, 0.5, 0.45, 1)
local COLOR_SELECTED = KColor(0.92, 0.86, 0.72, 1)
local COLOR_ERROR = KColor(1, 0.35, 0.35, 1)

local function getFont()
    if menuFont == nil then
        menuFont = Font()
        menuFont:Load("font/pftempestasevencondensed.fnt")
    end
    return menuFont
end

local function drawText(text, x, y, scale, color)
    scale = scale or 1
    color = color or COLOR_WHITE
    getFont():DrawStringScaled(text, x, y, scale, scale, color, 0, false)
end

local function drawTextAtMenu(worldPos, text, scale, color)
    local ok, screenPos = pcall(Isaac.WorldToMenuPosition, MENU_LAYOUT, worldPos)
    if not ok or not screenPos then
        return
    end
    drawText(text, screenPos.X, screenPos.Y, scale, color)
end

local function isMenuManagerActive()
    if not MenuManager or not MenuManager.IsActive then
        return false
    end
    return MenuManager.IsActive()
end

local function getActiveMenu()
    if not MenuManager or not MenuManager.GetActiveMenu then
        return nil
    end
    return MenuManager.GetActiveMenu()
end

local function actionTriggered(action)
    for i = 0, 7 do
        if Input.IsActionTriggered(action, i) then
            return true
        end
    end
    return false
end

local function actionPressed(action)
    for i = 0, 7 do
        if Input.IsActionPressed(action, i) then
            return true
        end
    end
    return false
end

local function keyTriggered(key)
    for i = 0, 7 do
        if Input.IsButtonTriggered(key, i) then
            return true
        end
    end
    return false
end

local function keyMenuUpTriggered()
    return keyTriggered(Keyboard.KEY_W)
end

local function keyMenuDownTriggered()
    return keyTriggered(Keyboard.KEY_S)
end

local function keyMenuConfirmTriggered()
    return keyTriggered(Keyboard.KEY_E)
end

local function keyMenuBackTriggered()
    return keyTriggered(Keyboard.KEY_Q)
end

local function logMenuDebug(message)
    if loggedMenuActionCount >= MAX_MENU_ACTION_LOGS then
        return
    end
    loggedMenuActionCount = loggedMenuActionCount + 1
    Isaac.DebugString("[IsaacRanked] " .. message)
end

function Menu.isOnGameMenu()
    return isMenuManagerActive() and getActiveMenu() == MENU_LAYOUT
end

function Menu.isOnRankedScreen()
    return Menu.rankedScreenOpen
end

function Menu.trackMenuChanges()
    if not isMenuManagerActive() then
        Menu.rankedScreenOpen = false
        Menu.savedInputMask = nil
        return
    end
end

function Menu.openRankedScreen()
    local active = getActiveMenu()
    if active ~= nil then
        Menu.previousMenu = active
    end

    if MenuManager and MenuManager.GetInputMask then
        Menu.savedInputMask = MenuManager.GetInputMask()
    end
    -- Keep default input mask; ranked menu uses dedicated keys (W/S/E/Q).

    -- Use a valid vanilla menu as backdrop for this dedicated panel.
    if MenuManager and MenuManager.SetActiveMenu then
        MenuManager.SetActiveMenu(MENU_LAYOUT)
    end

    Menu.rankedScreenOpen = true
    Menu.selectedAction = 1
    State.setError("")
    logMenuDebug("open ranked screen, inputMask=" .. tostring(Menu.savedInputMask))
end

function Menu.closeRankedScreen()
    if MenuManager and MenuManager.SetInputMask and Menu.savedInputMask ~= nil then
        MenuManager.SetInputMask(Menu.savedInputMask)
    end
    Menu.savedInputMask = nil

    if MenuManager and MenuManager.SetActiveMenu and Menu.previousMenu ~= nil then
        MenuManager.SetActiveMenu(Menu.previousMenu)
    end

    Menu.rankedScreenOpen = false
    Menu.selectedAction = 1
    logMenuDebug("close ranked screen")
end

function Menu.consumeRankedScreenInput(action)
    if action == ButtonAction.ACTION_MENUBACK then
        Menu.closeRankedScreen()
        return false
    end
    if action == ButtonAction.ACTION_MENUUP
        or action == ButtonAction.ACTION_MENUDOWN
        or action == ButtonAction.ACTION_MENUCONFIRM then
        return false
    end
end

function Menu.onMenuInputAction(entity, hook, action)
    if not isMenuManagerActive() then
        return
    end
    if Menu.rankedScreenOpen then
        if (action == ButtonAction.ACTION_MENUUP
            or action == ButtonAction.ACTION_MENUDOWN
            or action == ButtonAction.ACTION_MENUCONFIRM
            or action == ButtonAction.ACTION_MENUBACK)
            and loggedMenuCallbackCount < MAX_MENU_CALLBACK_LOGS then
            loggedMenuCallbackCount = loggedMenuCallbackCount + 1
            Isaac.DebugString("[IsaacRanked] menu callback entity=" .. tostring(type(entity))
                .. " hook=" .. tostring(hook) .. " action=" .. tostring(action))
        end

        return false
    end
end

function Menu.shouldBlockVanillaInput()
    return Menu.rankedScreenOpen
end

function Menu.handleRankedScreenInput()
    local function edge(_, keyEdge)
        return keyEdge
    end

    local backTriggered = edge("back", keyMenuBackTriggered())
    local upTriggered = edge("up", keyMenuUpTriggered())
    local downTriggered = edge("down", keyMenuDownTriggered())
    local confirmTriggered = edge("confirm", keyMenuConfirmTriggered())

    -- #region agent log
    if backTriggered or upTriggered or downTriggered or confirmTriggered then
        logMenuDebug("polled actions back=" .. tostring(backTriggered)
            .. " up=" .. tostring(upTriggered)
            .. " down=" .. tostring(downTriggered)
            .. " confirm=" .. tostring(confirmTriggered))
    end
    -- #endregion

    if backTriggered then
        Menu.closeRankedScreen()
        return
    end
    if upTriggered then
        Menu.selectedAction = Menu.selectedAction - 1
        if Menu.selectedAction < 1 then
            Menu.selectedAction = #actions
        end
        return
    end
    if downTriggered then
        Menu.selectedAction = Menu.selectedAction + 1
        if Menu.selectedAction > #actions then
            Menu.selectedAction = 1
        end
        return
    end
    if confirmTriggered and menuRenderFrame >= confirmCooldownUntilFrame then
        confirmCooldownUntilFrame = menuRenderFrame + 12
        Menu.activateAction(Menu.selectedAction)
        return
    end
end

-- #region agent log
local _dbgUpdateInputCount = 0
local _dbgMaxUpdateInputLogs = 5
-- #endregion

function Menu.updateInput()
    -- #region agent log
    _dbgUpdateInputCount = _dbgUpdateInputCount + 1
    if _dbgUpdateInputCount <= _dbgMaxUpdateInputLogs then
        local mmExists = (MenuManager ~= nil)
        local isActiveFn = (MenuManager ~= nil and MenuManager.IsActive ~= nil)
        local isActiveResult = nil
        if isActiveFn then
            local ok, val = pcall(MenuManager.IsActive)
            isActiveResult = ok and tostring(val) or ("ERR:" .. tostring(val))
        end
        local gameOk, gameFrame = pcall(function() return Game():GetFrameCount() end)
        Isaac.DebugString("[IsaacRanked][H1] updateInput #" .. _dbgUpdateInputCount
            .. " menuRenderFrame=" .. tostring(menuRenderFrame)
            .. " lastProcessed=" .. tostring(lastInputFrameProcessed)
            .. " isActiveResult=" .. tostring(isActiveResult))
    end
    -- #endregion

    if not isMenuManagerActive() then
        return
    end

    menuRenderFrame = menuRenderFrame + 1

    if menuRenderFrame == lastInputFrameProcessed then
        return
    end
    lastInputFrameProcessed = menuRenderFrame

    if keyTriggered(Menu.OPEN_KEY) and not Menu.rankedScreenOpen then
        logMenuDebug("F6 key trigger detected")
        Menu.openRankedScreen()
        return
    end

    if Menu.rankedScreenOpen then
        Menu.handleRankedScreenInput()
    end
end

local function truncateMenuText(text, maxChars)
    if not text or text == "" then
        return ""
    end
    if #text <= maxChars then
        return text
    end
    return string.sub(text, 1, maxChars - 3) .. "..."
end

function Menu.activateAction(index)
    local action = actions[index]
    logMenuDebug("activate action=" .. tostring(action))
    if action == "Queue Ranked" then
        if not Integrity.canQueue(true) then
            logMenuDebug("queue ranked blocked: " .. tostring(State.current.errorMessage))
            -- #region agent log
            local DebugLog = _G._IsaacRanked_DebugLog or include("scripts.debug_log")
            DebugLog.write("H4", "menu.lua:activateAction", "queue ranked blocked in menu", {
                runId = "debug-queue",
                errorMessage = State.current.errorMessage,
            })
            -- #endregion
            return
        end
        if not Config.hasRepentogon() then
            State.setError("REPENTOGON is required.")
            logMenuDebug("queue ranked blocked: repentogon missing")
            return
        end
        State.setError("")
        local joinOk = Network.startQueueJoin()
        if not joinOk then
            logMenuDebug("queue ranked blocked: send failed")
            return
        end
        State.current.matchState = State.MATCH_STATES.connecting
        State.setStatus("Connecting to matchmaking server...")
        logMenuDebug("queue ranked connecting join=" .. tostring(joinOk))
        -- #region agent log
        local DebugLog = _G._IsaacRanked_DebugLog or include("scripts.debug_log")
        DebugLog.write("H4", "menu.lua:activateAction", "queue ranked sent", {
            runId = "debug-queue",
            joinOk = joinOk,
            bridgeDir = Config.getBridgeDir(),
            errorMessage = State.current.errorMessage,
        })
        -- #endregion
    elseif action == "Cancel Queue" then
        local leaveOk = Network.queueLeave()
        Integrity.endRunProtection()
        State.resetMatch()
        State.setStatus("Queue cancelled")
        logMenuDebug("cancel queue sent leave=" .. tostring(leaveOk))
    elseif action == "Mock Match" then
        -- Allow mock testing even when options.ini cannot be verified.
        if not Integrity.canQueue(false) then
            logMenuDebug("mock blocked: " .. tostring(State.current.errorMessage))
            return
        end
        State.current.mockMode = true
        -- #region agent log
        Isaac.DebugString("[IsaacRanked][H2] menu State mockMode=" .. tostring(State.current.mockMode)
            .. " stateId=" .. tostring(State))
        -- #endregion
        local helloOk = Network.hello()
        local joinOk = Network.queueJoin()
        logMenuDebug("mock sent hello=" .. tostring(helloOk) .. " join=" .. tostring(joinOk))
    elseif action == "Reconnect" then
        if State.loadActiveMatch() then
            State.setStatus("Reconnected to active match " .. State.current.matchConfig.matchId)
        end
        local helloOk = Network.hello()
        logMenuDebug("reconnect sent hello=" .. tostring(helloOk))
    end
end

function Menu.renderGameMenuEntry()
    drawTextAtMenu(Menu.HINT_POS, "Press F6 to open Isaac Ranked", 0.8, COLOR_DIM)
    if State.current.errorMessage ~= "" then
        drawTextAtMenu(Menu.HINT_POS + Vector(0, 14), truncateMenuText(State.current.errorMessage, 52), 0.75, COLOR_ERROR)
    end
end

function Menu.renderRankedScreen()
    local base = Menu.RANKED_SCREEN_POS
    local line = Menu.RANKED_SCREEN_LINE

    drawTextAtMenu(base, "ISAAC RANKED", 1.25, COLOR_SELECTED)
    drawTextAtMenu(base + Vector(0, line), "Rating: " .. tostring(State.current.rating), 0.9)
    drawTextAtMenu(base + Vector(0, line * 2), "State: " .. tostring(State.current.matchState), 0.85)

    local yLines = 3

    if State.current.objective then
        drawTextAtMenu(base + Vector(0, line * yLines), "Objective: " .. State.current.objective.name, 0.85, COLOR_SELECTED)
        yLines = yLines + 1
    end

    if State.current.matchConfig then
        drawTextAtMenu(base + Vector(0, line * yLines), "Character: " .. tostring(State.current.matchConfig.characterName), 0.85)
        yLines = yLines + 1
        drawTextAtMenu(base + Vector(0, line * yLines), "Seed: " .. Match.getAssignedSeedString(), 0.85)
        yLines = yLines + 1
        if State.current.matchConfig.opponent then
            drawTextAtMenu(base + Vector(0, line * yLines), "Opponent: " .. State.current.matchConfig.opponent.displayName, 0.85)
            yLines = yLines + 1
        end
    end

    if State.current.opponentProgress then
        local p = State.current.opponentProgress
        drawTextAtMenu(base + Vector(0, line * yLines), string.format("Opponent: floor %d (%dms)", p.floor or 0, p.elapsedMs or 0), 0.8)
        yLines = yLines + 1
    end

    if State.current.statusMessage ~= "" then
        drawTextAtMenu(base + Vector(0, line * yLines), State.current.statusMessage, 0.8)
        yLines = yLines + 1
    end
    if State.current.errorMessage ~= "" then
        drawTextAtMenu(base + Vector(0, line * yLines), truncateMenuText(State.current.errorMessage, 52), 0.8, COLOR_ERROR)
        yLines = yLines + 1
    end

    yLines = yLines + 1
    for i, action in ipairs(actions) do
        local prefix = (i == Menu.selectedAction) and "> " or "  "
        drawTextAtMenu(base + Vector(0, line * yLines), prefix .. action, 0.9)
        yLines = yLines + 1
    end
    drawTextAtMenu(base + Vector(0, line * yLines), "Controls: W/S move, E select, Q back", 0.75, COLOR_DIM)
    yLines = yLines + 1

    if not Config.hasRepentogon() then
        drawTextAtMenu(base + Vector(0, line * yLines), "Install REPENTOGON to enable ranked play.", 0.75, COLOR_DIM)
    elseif not Config.getDocumentsRoot() then
        drawTextAtMenu(base + Vector(0, line * yLines), "Re-run install-mod.cmd to configure paths.", 0.75, COLOR_DIM)
    end
end

function Menu.render()
    if not isMenuManagerActive() then
        return
    end
    if Menu.rankedScreenOpen then
        Menu.renderRankedScreen()
    elseif Menu.isOnGameMenu() then
        Menu.renderGameMenuEntry()
    end
end

_G._IsaacRanked_Menu = Menu
return Menu
