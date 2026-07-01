if _G._IsaacRanked_Results then return _G._IsaacRanked_Results end

local Config = include("scripts.config")
local State = include("scripts.state")
local Integrity = include("scripts.integrity")
local Network = include("scripts.network")
local Objective = include("scripts.objective")

local Results = {}

local lastProgressFrame = 0
local playerDead = false
local runCompleted = false
local returnToMenuAtFrame = -1
local pendingMenuReturn = false

local function getElapsedMs()
    if not State.current.runStartedAtFrame then
        return 0
    end
    local frames = Game():GetFrameCount() - State.current.runStartedAtFrame
    return math.floor((frames / 30) * 1000)
end

local function getFloorInfo()
    local level = Game():GetLevel()
    return level:GetStage(), level:GetStageType(), level:GetCurrentRoomIndex()
end

function Results.onGameStarted()
    playerDead = false
    runCompleted = false
    returnToMenuAtFrame = -1
    pendingMenuReturn = false
    State.current.runStartedAtFrame = Game():GetFrameCount()
    local stage, stageType = getFloorInfo()
    State.current.currentStage = stage
    State.current.currentFloor = stage
    State.current.currentStageType = stageType
end

function Results.onNewLevel()
    if State.current.matchState ~= State.MATCH_STATES.in_progress then
        return
    end
    local stage, stageType = getFloorInfo()
    State.current.currentStage = stage
    State.current.currentFloor = stage
    State.current.currentStageType = stageType
end

function Results.onPlayerUpdate(player)
    if State.current.matchState ~= State.MATCH_STATES.in_progress then
        return
    end
    if player and (not player:WillPlayerRevive()) and player:IsDead() and not playerDead then
        playerDead = true
        Results.submitResult("loss", "player_death")
    end
end

function Results.shouldBlockRunInput()
    return playerDead
        or runCompleted
        or State.current.returningToMenu
        or pendingMenuReturn
end

function Results.onInputAction(entity, hook, action)
    if not Results.shouldBlockRunInput() then
        return
    end
    if hook ~= InputHook.IS_ACTION_TRIGGERED and hook ~= InputHook.IS_ACTION_PRESSED then
        return
    end
    if action == ButtonAction.ACTION_MENUCONFIRM
        or action == ButtonAction.ACTION_CONFIRM
        or action == ButtonAction.ACTION_MENUBACK
        or action == ButtonAction.ACTION_MENUUP
        or action == ButtonAction.ACTION_MENUDOWN then
        -- #region agent log
        Isaac.DebugString("[IsaacRanked][H4] blocked input action=" .. tostring(action))
        -- #endregion
        return false
    end
end

function Results.checkWinCondition()
    local obj = Objective.getActive()
    if not obj then
        return false
    end

    local game = Game()
    local level = game:GetLevel()
    local room = game:GetRoom()
    local stage = level:GetStage()
    local stageType = level:GetStageType()
    local isBossRoom = room:GetType() == RoomType.ROOM_BOSS

    if not isBossRoom then
        return false
    end

    if stage ~= obj.finalStage then
        return false
    end

    if obj.finalType ~= nil and stageType ~= obj.finalType then
        return false
    end

    return true
end

function Results.onGameEnd(isGameOver)
    -- #region agent log
    Isaac.DebugString("[IsaacRanked][H3] onGameEnd isGameOver=" .. tostring(isGameOver)
        .. " pendingMenuReturn=" .. tostring(pendingMenuReturn)
        .. " runCompleted=" .. tostring(runCompleted)
        .. " matchState=" .. tostring(State.current.matchState))
    -- #endregion

    if pendingMenuReturn and not State.current.returningToMenu then
        pendingMenuReturn = false
        returnToMenuAtFrame = -1
        Results.finishAndReturnToMenu()
        Integrity.endRunProtection()
        return
    end

    if State.current.matchState ~= State.MATCH_STATES.in_progress then
        return
    end
    if not runCompleted and not playerDead then
        Results.submitResult("dnf", "game_end")
    end
    Integrity.endRunProtection()
end

function Results.onGameExit()
    -- #region agent log
    Isaac.DebugString("[IsaacRanked][H2] onGameExit returningToMenu="
        .. tostring(State.current.returningToMenu)
        .. " launchingRun=" .. tostring(State.current.launchingRun)
        .. " matchState=" .. tostring(State.current.matchState))
    -- #endregion

    if State.current.returningToMenu or State.current.launchingRun then
        if State.current.launchingRun then
            State.current.launchingRun = false
        end
        if State.current.returningToMenu then
            State.current.returningToMenu = false
        end
        return
    end

    if State.isActiveMatch() then
        local matchId = State.current.matchConfig and State.current.matchConfig.matchId
        if matchId then
            Network.sendForfeit(matchId, "game_exit")
        end
    end
end

local function scheduleReturnToMenu(delayFrames)
    returnToMenuAtFrame = Game():GetFrameCount() + (delayFrames or 30)
end

function Results.finishAndReturnToMenu()
    if State.current.returningToMenu then
        return
    end

    -- #region agent log
    Isaac.DebugString("[IsaacRanked][H3] finishAndReturnToMenu called")
    -- #endregion

    local statusMessage = State.current.statusMessage
    Objective.clear()
    Integrity.endRunProtection()
    State.resetMatch()
    State.saveActiveMatch()
    if statusMessage ~= "" then
        State.setStatus(statusMessage)
    end

    local Match = _G._IsaacRanked_Match
    if Match and Match.returnToMainMenu then
        Match.returnToMainMenu()
    end
end

function Results.submitResult(result, reason)
    if runCompleted or State.current.integrityViolation then
        if State.current.integrityViolation then
            result = "loss"
            reason = State.current.integrityReason or "integrity_violation"
        end
    end

    runCompleted = true
    State.current.matchState = State.MATCH_STATES.finished
    State.current.elapsedMs = getElapsedMs()

    local matchId = State.current.matchConfig and State.current.matchConfig.matchId
    if not matchId then
        return
    end

    local seeds = Game():GetSeeds()
    Network.sendMatchResult({
        matchId = matchId,
        result = result,
        elapsedMs = State.current.elapsedMs,
        floor = State.current.currentFloor,
        reason = reason,
        actualSeed = seeds:GetStartSeed(),
        actualPlayerType = Game():GetPlayer(0):GetPlayerType(),
    })

    Integrity.endRunProtection()

    if result == "win" then
        State.setStatus(string.format("Victory! (%s)", reason or "win"))
    elseif result == "loss" then
        State.setStatus("Defeat")
    elseif result == "invalid" then
        State.setStatus("Match invalid")
    end

    if result == "win" or result == "loss" or result == "invalid" then
        Results.finishAndReturnToMenu()
    end
end

function Results.checkMockOpponentWin()
    if runCompleted or playerDead then
        return
    end
    if not State.current.mockMode then
        return
    end
    if State.current.matchState ~= State.MATCH_STATES.in_progress then
        return
    end

    Network = Network or _G._IsaacRanked_Network
    if not Network or not Network.getMockOpponentProgress then
        return
    end

    local mock = Network.getMockOpponentProgress()
    if not mock or mock.alive == false then
        return
    end

    local obj = Objective.getActive()
    if not obj then
        return
    end

    if mock.stage >= obj.finalStage then
        Results.submitResult("loss", "opponent_completed_objective")
    end
end

function Results.tick()
    if returnToMenuAtFrame >= 0 and Game():GetFrameCount() >= returnToMenuAtFrame then
        returnToMenuAtFrame = -1
        Results.finishAndReturnToMenu()
        return
    end

    if State.current.integrityViolation and not runCompleted then
        Results.submitResult("loss", State.current.integrityReason)
        return
    end

    if State.current.matchState ~= State.MATCH_STATES.in_progress then
        return
    end

    local frame = Game():GetFrameCount()
    if frame - lastProgressFrame < 30 then
        return
    end
    lastProgressFrame = frame

    local matchId = State.current.matchConfig and State.current.matchConfig.matchId
    if not matchId then
        return
    end

    Network.sendProgress({
        matchId = matchId,
        floor = State.current.currentFloor,
        stage = State.current.currentStage,
        stageType = State.current.currentStageType,
        elapsedMs = getElapsedMs(),
        alive = not playerDead,
    })

    if State.current.mockMode then
        Results.checkMockOpponentWin()
    end

    local room = Game():GetRoom()
    -- #region agent log
    if room == nil then
        Isaac.DebugString("[IsaacRanked][H1] tick win-check skipped: room is nil")
    end
    -- #endregion
    if room and room:IsClear() and Results.checkWinCondition() and not runCompleted then
        Results.submitResult("win", "win_condition_met")
    end
end

function Results.applyServerResolution(msg)
    if msg.newRating then
        State.current.rating = msg.newRating
    end

    local result = msg.result
    local reason = msg.reason or "match_resolved"

    -- #region agent log
    Isaac.DebugString(string.format(
        "[IsaacRanked][DBG] applyServerResolution result=%s reason=%s inProgress=%s",
        tostring(result),
        tostring(reason),
        tostring(State.current.matchState == State.MATCH_STATES.in_progress)
    ))
    local DebugLog = _G._IsaacRanked_DebugLog
    if DebugLog then
        DebugLog.write("H4", "results.lua:applyServerResolution", "server match_resolved", {
            runId = "post-fix",
            result = result,
            reason = reason,
            matchState = State.current.matchState,
            runCompleted = runCompleted,
        })
    end
    -- #endregion

    if not runCompleted and State.current.matchState == State.MATCH_STATES.in_progress then
        if result == "win" or result == "loss" then
            runCompleted = true
            State.current.matchState = State.MATCH_STATES.finished
            State.current.elapsedMs = getElapsedMs()
            Integrity.endRunProtection()
            if result == "win" then
                State.setStatus(string.format("Victory! (%s)", reason))
            else
                State.setStatus("Defeat")
            end
            Results.finishAndReturnToMenu()
            State.saveActiveMatch()
            return
        end
    end

    State.setStatus(string.format("Match resolved (%s, %+d Elo)", result or "?", msg.ratingDelta or 0))
    Integrity.endRunProtection()
    State.saveActiveMatch()
end

_G._IsaacRanked_Results = Results
return Results
