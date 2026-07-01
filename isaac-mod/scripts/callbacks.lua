if _G._IsaacRanked_Callbacks then return _G._IsaacRanked_Callbacks end

local Config = include("scripts.config")
local State = include("scripts.state")
local Network = include("scripts.network")
local Menu = include("scripts.menu")
local Match = include("scripts.match")
local Results = include("scripts.results")
local Integrity = include("scripts.integrity")
local ModWhitelist = include("scripts.mod_whitelist")
local Anticheat = include("scripts.anticheat")
local Objective = include("scripts.objective")
local Progress = include("scripts.progress")

local Callbacks = {}

local initialized = false
local lastHeartbeatFrame = 0
local loggedMenuShape = false

function Callbacks.init(mod)
    if initialized then
        return
    end
    initialized = true
    Config.init(mod)
    State.current.playerId = Config.getPlayerId()
    State.current.displayName = Config.getDisplayName()
    ModWhitelist.captureAtStartup()

    if mod.AddPriorityCallback and ModCallbacks.MC_INPUT_ACTION and CallbackPriority then
        mod:AddPriorityCallback(
            ModCallbacks.MC_INPUT_ACTION,
            CallbackPriority.IMPORTANT,
            function(_, entity, hook, action)
                return Anticheat.onInputAction(entity, hook, action)
            end
        )
    end

    -- #region agent log
    local DebugLog = _G._IsaacRanked_DebugLog
    if DebugLog then
        DebugLog.write("H4", "callbacks.lua:init", "config shape in callbacks", {
            configType = type(Config),
            getBridgeDirType = type(Config.getBridgeDir),
            runId = "post-fix",
        })
        DebugLog.write("H2", "callbacks.lua:init", "mod init completed", {
            menuModuleType = type(Menu),
            runId = "post-fix",
        })
    end
    -- #endregion

    -- MC_MENU_INPUT_ACTION intentionally not used for ranked controls:
    -- it can be very noisy and contributes to menu stutter on some setups.
end

function Callbacks.onPostGameStarted(isContinued)
    if isContinued then
        return
    end

    if State.current.matchState == "starting" or State.current.matchState == "matched" then
        Match.onGameStarted()
        Results.onGameStarted()
        Integrity.onRunStarted()
    end
end

function Callbacks.onPostUpdate()
    Network.tick()
    if State.current.matchState == State.MATCH_STATES.in_progress then
        Anticheat.tick()
    end
    Results.tick()

    local frame = Game():GetFrameCount()
    if frame - lastHeartbeatFrame >= 90 then
        lastHeartbeatFrame = frame
        if State.isInQueue() or State.isActiveMatch() then
            Network.sendHeartbeat()
        end
    end
end

function Callbacks.onPostRender()
    if MenuManager and MenuManager.IsActive and MenuManager.IsActive() then
        Menu.trackMenuChanges()
        Menu.updateInput()
    end
    Menu.render()
    Objective.renderHUD()
    Progress.renderHUD()
    if State.current.matchState == State.MATCH_STATES.in_progress then
        Anticheat.pollConsoleVisibility()
    end
end

function Callbacks.onMainMenuRender()
    -- #region agent log
    if not loggedMenuShape then
        loggedMenuShape = true
        Isaac.DebugString("[IsaacRanked] Menu type=" .. tostring(type(Menu))
            .. " trackMenuChanges=" .. tostring(type(Menu.trackMenuChanges))
            .. " updateInput=" .. tostring(type(Menu.updateInput))
            .. " render=" .. tostring(type(Menu.render)))
    end
    -- #endregion

    Menu.trackMenuChanges()
    Menu.updateInput()
    Menu.render()

    if Menu.isOnGameMenu() or Menu.isOnRankedScreen() then
        local frame = Game():GetFrameCount()
        if frame % 2 == 0 then
            Network.tick()
        end
    end
end

function Callbacks.onPostNewLevel()
    Results.onNewLevel()
end

function Callbacks.onPlayerUpdate(player)
    Results.onPlayerUpdate(player)
end

function Callbacks.onInputAction(entity, hook, action)
    return Results.onInputAction(entity, hook, action)
end

function Callbacks.onGameEnd(isGameOver)
    Results.onGameEnd(isGameOver)
end

function Callbacks.onPreLevelSelect(stage, stageType)
    return Objective.onPreLevelSelect(stage, stageType)
end

function Callbacks.onExecuteCmd(cmd, params)
    return Integrity.onExecuteCmd(cmd, params)
end

function Callbacks.onPostGetCollectible(collectibleType)
    Anticheat.onPostGetCollectible(collectibleType)
end

function Callbacks.onPreGetCollectible(collectibleType)
    Anticheat.onPreGetCollectible(collectibleType)
end

function Callbacks.onPrePickupCollision(pickup, collider)
    Anticheat.onPrePickupCollision(pickup, collider)
end

function Callbacks.onPostAddCollectible(collectibleType, charge, firstTime, slot, varData, player)
    Anticheat.onPostAddCollectible(collectibleType, charge, firstTime, slot, varData, player)
end

function Callbacks.onGameExit()
    Results.onGameExit()
end

_G._IsaacRanked_Callbacks = Callbacks
return Callbacks
