if _G._IsaacRanked_State then return _G._IsaacRanked_State end

local State = {}
local Config = include("scripts.config")

State.MATCH_STATES = {
    idle = "idle",
    queued = "queued",
    connecting = "connecting",
    matched = "matched",
    starting = "starting",
    in_progress = "in_progress",
    finished = "finished",
    forfeited = "forfeited",
    invalid = "invalid",
}

State.current = {
    matchState = "idle",
    playerId = nil,
    displayName = nil,
    rating = 1000,
    placementMatchesRemaining = 5,
    queuePosition = 0,
    estimatedWaitSec = 0,
    matchConfig = nil,
    opponentProgress = nil,
    runStartedAtFrame = nil,
    elapsedMs = 0,
    currentFloor = 1,
    currentStage = 1,
    currentStageType = 0,
    integrityViolation = false,
    integrityReason = nil,
    lastHeartbeatFrame = 0,
    statusMessage = "",
    errorMessage = "",
    mockMode = false,
    objective = nil,
    returningToMenu = false,
    launchingRun = false,
}

function State.resetMatch()
    State.current.matchState = State.MATCH_STATES.idle
    State.current.matchConfig = nil
    State.current.opponentProgress = nil
    State.current.runStartedAtFrame = nil
    State.current.elapsedMs = 0
    State.current.currentFloor = 1
    State.current.currentStage = 1
    State.current.currentStageType = 0
    State.current.integrityViolation = false
    State.current.integrityReason = nil
    State.current.statusMessage = ""
    State.current.mockMode = false
    State.current.objective = nil
    State.current.returningToMenu = false
    State.current.launchingRun = false
end

function State.saveActiveMatch()
    if type(Config.loadMemoryState) ~= "function" then
        Isaac.DebugString("[IsaacRanked] state.saveActiveMatch missing Config.loadMemoryState")
        return
    end
    local state = Config.loadMemoryState()

    if State.current.matchConfig then
        state.activeMatch = {
            matchState = State.current.matchState,
            matchConfig = State.current.matchConfig,
        }
    else
        state.activeMatch = nil
    end

    Config.saveMemoryState()
end

function State.loadActiveMatch()
    if type(Config.loadMemoryState) ~= "function" then
        Isaac.DebugString("[IsaacRanked] state.loadActiveMatch missing Config.loadMemoryState")
        return false
    end
    local state = Config.loadMemoryState()
    local payload = state.activeMatch

    if payload == nil or payload.matchConfig == nil then
        return false
    end

    State.current.matchState = payload.matchState or State.MATCH_STATES.matched
    State.current.matchConfig = payload.matchConfig
    return true
end

function State.setStatus(msg)
    State.current.statusMessage = msg or ""
end

function State.setError(msg)
    State.current.errorMessage = msg or ""
end

function State.isActiveMatch()
    local s = State.current.matchState
    return s == "matched" or s == "starting" or s == "in_progress"
end

function State.isInQueue()
    return State.current.matchState == State.MATCH_STATES.queued
        or State.current.matchState == State.MATCH_STATES.connecting
end

_G._IsaacRanked_State = State
return State
