local IsaacRanked = RegisterMod("Isaac Ranked", 1)

IsaacRanked.VERSION = "0.1.0"
IsaacRanked.PROTOCOL_VERSION = 1

_G._IsaacRanked_ConsoleCheck = { known = false, enabled = nil }
do
    local ok, preflight = pcall(include, "scripts.preflight")
    if ok and type(preflight) == "table" and preflight.vanillaConsoleEnabled ~= nil then
        _G._IsaacRanked_ConsoleCheck.known = true
        _G._IsaacRanked_ConsoleCheck.enabled = preflight.vanillaConsoleEnabled == true
    end
end

Isaac.DebugString("[IsaacRanked][DBG] console check known="
    .. tostring(_G._IsaacRanked_ConsoleCheck.known)
    .. " enabled=" .. tostring(_G._IsaacRanked_ConsoleCheck.enabled))

local Callbacks = include("scripts.callbacks")

IsaacRanked:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinued)
    Callbacks.onPostGameStarted(isContinued)
end)

IsaacRanked:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    Callbacks.onPostUpdate()
end)

if ModCallbacks.MC_MAIN_MENU_RENDER then
    IsaacRanked:AddCallback(ModCallbacks.MC_MAIN_MENU_RENDER, function()
        Callbacks.onMainMenuRender()
    end)
end

IsaacRanked:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    Callbacks.onPostRender()
end)

-- Ranked menu uses dedicated keyboard polling in scripts/menu.lua.

IsaacRanked:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, function()
    Callbacks.onPostNewLevel()
end)

IsaacRanked:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, function(_, player)
    Callbacks.onPlayerUpdate(player)
end)

IsaacRanked:AddCallback(ModCallbacks.MC_INPUT_ACTION, function(_, entity, hook, action)
    return Callbacks.onInputAction(entity, hook, action)
end)

IsaacRanked:AddCallback(ModCallbacks.MC_POST_GAME_END, function(_, isGameOver)
    Callbacks.onGameEnd(isGameOver)
end)

if ModCallbacks.MC_PRE_LEVEL_SELECT then
    IsaacRanked:AddCallback(ModCallbacks.MC_PRE_LEVEL_SELECT, function(_, stage, stageType)
        return Callbacks.onPreLevelSelect(stage, stageType)
    end)
end

if ModCallbacks.MC_EXECUTE_CMD then
    IsaacRanked:AddCallback(ModCallbacks.MC_EXECUTE_CMD, function(_, cmd, params)
        return Callbacks.onExecuteCmd(cmd, params)
    end)
end

if ModCallbacks.MC_POST_GET_COLLECTIBLE then
    IsaacRanked:AddCallback(ModCallbacks.MC_POST_GET_COLLECTIBLE, function(_, collectibleType)
        Callbacks.onPostGetCollectible(collectibleType)
    end)
end

if ModCallbacks.MC_PRE_GET_COLLECTIBLE then
    IsaacRanked:AddCallback(ModCallbacks.MC_PRE_GET_COLLECTIBLE, function(_, collectibleType)
        Callbacks.onPreGetCollectible(collectibleType)
    end)
end

if ModCallbacks.MC_PRE_PICKUP_COLLISION then
    IsaacRanked:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, function(_, pickup, collider)
        Callbacks.onPrePickupCollision(pickup, collider)
    end)
end

if ModCallbacks.MC_POST_ADD_COLLECTIBLE then
    IsaacRanked:AddCallback(ModCallbacks.MC_POST_ADD_COLLECTIBLE, function(_, collectibleType, charge, firstTime, slot, varData, player)
        Callbacks.onPostAddCollectible(collectibleType, charge, firstTime, slot, varData, player)
    end)
end

if ModCallbacks.MC_PRE_GAME_EXIT then
    IsaacRanked:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_)
        Callbacks.onGameExit()
    end)
end

Callbacks.init(IsaacRanked)

return IsaacRanked
