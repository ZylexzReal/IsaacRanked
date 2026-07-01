if _G._IsaacRanked_Network then return _G._IsaacRanked_Network end

local json = include("scripts.json")
local Config = include("scripts.config")
local HttpBridge = include("scripts.http_bridge")
local State = include("scripts.state")
local Match -- resolved lazily to avoid circular include at load time

local Network = {}

Network._inbox = {}
Network._mockOpponent = nil

local requestCounter = 0
local pendingResponses = {}
local loggedStateShape = false
local loggedBridgeTransport = false
local loggedSocketProbe = false
local loggedDirectoryMissing = false
local cachedSocketModule = nil
local socketProbeDone = false
local socketProbeError = nil
local lastInboxVersion = 0
local loggedInboxIncludeDiag = false
local CONNECTION_TIMEOUT_TICKS = 240

Network._tickFrame = 0
Network._awaitingHelloAck = false
Network._awaitingQueueUpdate = false
Network._connectionDeadline = nil
Network._pendingUnlockedCharacters = nil
Network._serverConnected = false
Network._pendingQueueJoin = false

local function getBridgeHost()
    return Config.getBridgeHost()
end

local function getBridgePort()
    return Config.getBridgePort()
end

local function nextRequestId()
    requestCounter = requestCounter + 1
    return "req-" .. tostring(requestCounter) .. "-" .. tostring(Game() and Game():GetFrameCount() or 0)
end

local function logBridgeTransport(message)
    if loggedBridgeTransport then
        return
    end
    loggedBridgeTransport = true
    Isaac.DebugString(message)
end

local function getSocketModule()
    if socketProbeDone then
        return cachedSocketModule
    end

    socketProbeDone = true

    if type(require) == "function" then
        local ok, mod = pcall(require, "socket")
        if ok and type(mod) == "table" and type(mod.tcp) == "function" then
            cachedSocketModule = mod
            if not loggedBridgeTransport then
                loggedBridgeTransport = true
                Isaac.DebugString("[IsaacRanked][DBG] bridge transport=require(socket)")
            end
            return mod
        end
        if not ok then
            socketProbeError = tostring(mod)
        end
    end

    if package and type(package.loaded) == "table" and type(package.loaded.socket) == "table" then
        cachedSocketModule = package.loaded.socket
        if not loggedBridgeTransport then
            loggedBridgeTransport = true
            Isaac.DebugString("[IsaacRanked][DBG] bridge transport=package.loaded.socket")
        end
        return cachedSocketModule
    end

    if type(socket) == "table" and type(socket.tcp) == "function" then
        cachedSocketModule = socket
        if not loggedBridgeTransport then
            loggedBridgeTransport = true
            Isaac.DebugString("[IsaacRanked][DBG] bridge transport=global socket")
        end
        return socket
    end

    cachedSocketModule = false
    if not loggedSocketProbe then
        loggedSocketProbe = true
        Isaac.DebugString("[IsaacRanked][DBG] bridge socket unavailable require="
            .. tostring(type(require)) .. " err=" .. tostring(socketProbeError))
    end
    return nil
end

local function isIoAvailable()
    return type(io) == "table" and type(io.open) == "function"
end

local deliverBridgeResponse

local function readInboxFromInclude()
    if package and type(package.loaded) == "table" then
        package.loaded["scripts.bridge_inbox"] = nil
    end

    local ok, result = pcall(include, "scripts.bridge_inbox")
    if type(_G._IsaacRanked_InboxEnvelope) == "string" then
        return _G._IsaacRanked_InboxEnvelope
    end

    if ok and type(result) == "string" and result ~= "" and result ~= "{}" then
        return result
    end

    if not loggedInboxIncludeDiag and Network._awaitingHelloAck then
        loggedInboxIncludeDiag = true
        -- #region agent log
        Isaac.DebugString("[IsaacRanked][DBG] inbox include probe ok=" .. tostring(ok)
            .. " type=" .. tostring(type(result))
            .. " err=" .. tostring(not ok and result or "")
            .. " loadfile=" .. tostring(type(loadfile)))
        -- #endregion
    end

    return nil
end

local function readLogBridgeInboxRaw()
    local bestRaw = nil
    local bestVersion = -1

    local function considerRaw(raw)
        if not raw or raw == "" or raw == "{}" then
            return
        end

        local ok, envelope = pcall(json.decode, raw)
        if ok and type(envelope) == "table" then
            local version = tonumber(envelope.version) or 0
            if version > bestVersion then
                bestVersion = version
                bestRaw = raw
            end
        end
    end

    considerRaw(readInboxFromInclude())

    if type(_G._IsaacRanked_InboxEnvelope) == "string" then
        considerRaw(_G._IsaacRanked_InboxEnvelope)
    end

    return bestRaw
end

local function pollLogBridgeInbox()
    local raw = readLogBridgeInboxRaw()
    if not raw or raw == "" or raw == "{}" then
        return
    end

    local okDecode, envelope = pcall(json.decode, raw)
    if not okDecode or type(envelope) ~= "table" then
        return
    end

    local version = tonumber(envelope.version) or 0
    local responses = envelope.responses
    if type(responses) ~= "table" then
        return
    end

    local hasPendingMatch = false
    for _, response in ipairs(responses) do
        if response and response.requestId and pendingResponses[response.requestId] then
            hasPendingMatch = true
            break
        end
    end

    if version < lastInboxVersion then
        -- #region agent log
        Isaac.DebugString("[IsaacRanked][DBG] inbox version reset server="
            .. tostring(version) .. " client=" .. tostring(lastInboxVersion))
        -- #endregion
        lastInboxVersion = 0
    end

    if version <= lastInboxVersion and not hasPendingMatch then
        return
    end

    local deliveredAny = false
    for _, response in ipairs(responses) do
        if response and response.requestId and pendingResponses[response.requestId] then
            pendingResponses[response.requestId] = nil
            deliverBridgeResponse(response)
            deliveredAny = true
        end
    end

    if deliveredAny or version > lastInboxVersion then
        -- #region agent log
        Isaac.DebugString("[IsaacRanked][DBG] inbox poll version=" .. tostring(version)
            .. " responses=" .. tostring(#responses)
            .. " delivered=" .. tostring(deliveredAny)
            .. " pendingMatch=" .. tostring(hasPendingMatch))
        -- #endregion
        lastInboxVersion = math.max(lastInboxVersion, version)
    end
end

local function sendBridgeRequestViaLog(message)
    local requestId = nextRequestId()
    local payload = json.encode({
        requestId = requestId,
        message = message,
    })

    Isaac.DebugString("[IsaacRanked][BRIDGE_SEND] " .. payload)
    pendingResponses[requestId] = true
    return true, nil
end

local function httpPostBridge(payloadJson)
    local body, err, transport = HttpBridge.postBridge(
        payloadJson,
        getBridgeHost(),
        getBridgePort()
    )
    if transport and not loggedBridgeTransport then
        loggedBridgeTransport = true
        Isaac.DebugString("[IsaacRanked][DBG] bridge transport=" .. transport)
    end
    if not body then
        return nil, err or "HTTP bridge request failed"
    end
    return body, nil
end

deliverBridgeResponse = function(response)
    if type(response) ~= "table" then
        return false, "Invalid bridge response"
    end

    if response.error and response.error ~= "" then
        return false, tostring(response.error)
    end

    if response.messages then
        -- #region agent log
        for _, msg in ipairs(response.messages) do
            Isaac.DebugString("[IsaacRanked][DBG] inbox msg type=" .. tostring(msg.type))
        end
        -- #endregion
        for _, msg in ipairs(response.messages) do
            table.insert(Network._inbox, msg)
        end
        Network.processInbound()
    end

    return true, nil
end

local function sendBridgeRequestViaHttp(message)
    local requestId = nextRequestId()
    local payload = json.encode({
        requestId = requestId,
        message = message,
    })

    local body, err = httpPostBridge(payload)
    if not body then
        return false, err or "HTTP bridge request failed"
    end

    local okDecode, response = pcall(json.decode, body)
    if not okDecode or type(response) ~= "table" then
        return false, "Could not parse bridge HTTP response"
    end

    return deliverBridgeResponse(response)
end

local function getSaveDataDirectory()
    if Directory == nil then
        if not loggedDirectoryMissing then
            loggedDirectoryMissing = true
            Isaac.DebugString("[IsaacRanked][DBG] bridge Directory global is nil; using HTTP bridge")
        end
        return nil
    end

    for _, getterName in ipairs({ "savedata", "Savedata", "saveData" }) do
        local getter = Directory[getterName]
        if type(getter) == "function" then
            local ok, saveDir = pcall(getter)
            if ok and saveDir then
                return saveDir
            end
        end
    end

    return nil
end

local function openDirectoryFile(dir, relativeName)
    if not dir then
        return nil
    end

    local relativePath = Config.BRIDGE_SUBDIR .. "/" .. relativeName
    for _, factory in ipairs({ "File", "file", "Get" }) do
        if type(dir[factory]) == "function" then
            local okFile, file = pcall(dir[factory], dir, relativePath)
            if okFile and file then
                return file
            end

            okFile, file = pcall(dir[factory], dir, Config.BRIDGE_SUBDIR, relativeName)
            if okFile and file then
                return file
            end
        end
    end

    return nil
end

local function writeBridgeFile(relativeName, content)
    local saveDir = getSaveDataDirectory()
    if not saveDir then
        return false, "File bridge unavailable"
    end

    local file = openDirectoryFile(saveDir, relativeName)
    if not file then
        return false, "File bridge unavailable"
    end

    for _, writer in ipairs({ "Write", "write", "WriteString", "write_string" }) do
        if type(file[writer]) == "function" then
            local ok, err = pcall(file[writer], file, content)
            if ok then
                return true, nil
            end
            return false, tostring(err)
        end
    end

    return false, "No supported file write method"
end

local function readBridgeFile(relativeName)
    local saveDir = getSaveDataDirectory()
    if not saveDir then
        return nil
    end

    local file = openDirectoryFile(saveDir, relativeName)
    if not file then
        return nil
    end

    for _, reader in ipairs({ "Read", "read", "ReadAll", "read_to_string" }) do
        if type(file[reader]) == "function" then
            local ok, content = pcall(file[reader], file)
            if ok and content then
                return content
            end
        end
    end

    return nil
end

local function sendBridgeRequestViaFile(message)
    local requestId = nextRequestId()
    local payload = json.encode({
        requestId = requestId,
        message = message,
    })

    local relativeName = "request-" .. requestId .. ".json"
    local ok, err = writeBridgeFile(relativeName, payload)
    if not ok then
        return false, err or "Could not write bridge request"
    end

    pendingResponses[requestId] = true
    return true, nil
end

local function bridgeIoPath(relativeName)
    local bridgeDir = Config.getBridgeDir()
    if not bridgeDir then
        return nil
    end
    return bridgeDir:gsub("\\", "/") .. "/" .. relativeName
end

local function writeBridgeIo(relativeName, content)
    if not isIoAvailable() then
        return false, "io unavailable in Isaac sandbox"
    end

    local path = bridgeIoPath(relativeName)
    if not path then
        return false, "Bridge directory unknown. Re-run install-mod.ps1."
    end

    local ok, err = pcall(function()
        local file = io.open(path, "w")
        if not file then
            error("could not open bridge file for write: " .. path)
        end
        file:write(content)
        file:close()
    end)
    if not ok then
        return false, tostring(err)
    end
    return true, nil
end

local function readBridgeIo(relativeName)
    if not isIoAvailable() then
        return nil
    end

    local path = bridgeIoPath(relativeName)
    if not path then
        return nil
    end

    local content
    local ok, err = pcall(function()
        local file = io.open(path, "r")
        if not file then
            return
        end
        content = file:read("*a")
        file:close()
    end)
    if not ok or not content or content == "" then
        return nil
    end
    return content
end

local function sendBridgeRequestViaIoFile(message)
    local requestId = nextRequestId()
    local payload = json.encode({
        requestId = requestId,
        message = message,
    })

    local ok, err = writeBridgeIo("request-" .. requestId .. ".json", payload)
    if not ok then
        return false, err or "Could not write bridge request"
    end

    pendingResponses[requestId] = true
    return true, nil
end

local function pollBridgeResponses()
    pollLogBridgeInbox()

    if isIoAvailable() then
        local bridgeDir = Config.getBridgeDir()
        if bridgeDir then
            for requestId, _ in pairs(pendingResponses) do
                local raw = readBridgeIo("response-" .. requestId .. ".json")
                if raw then
                    local ok, response = pcall(json.decode, raw)
                    if ok and response and response.messages then
                        pendingResponses[requestId] = nil
                        pcall(function()
                            local responsePath = bridgeIoPath("response-" .. requestId .. ".json")
                            if responsePath and os and os.remove then
                                os.remove(responsePath)
                            end
                        end)
                        deliverBridgeResponse(response)
                    end
                end
            end
        end
    end

    if not getSaveDataDirectory() then
        return
    end

    for requestId, _ in pairs(pendingResponses) do
        local relativeName = "response-" .. requestId .. ".json"
        local raw = readBridgeFile(relativeName)
        if raw then
            local ok, response = pcall(json.decode, raw)
            if ok and response and response.messages then
                pendingResponses[requestId] = nil
                deliverBridgeResponse(response)
            end
        end
    end
end

local function sendBridgeRequest(message)
    if Config.USE_LAUNCHER_BRIDGE then
        logBridgeTransport("[IsaacRanked][DBG] bridge transport=launcher-log")
        return sendBridgeRequestViaLog(message)
    end

    if not Config.isLocalDevServer() then
        logBridgeTransport("[IsaacRanked][DBG] bridge transport=http-remote")
        return sendBridgeRequestViaHttp(message)
    end

    if getSaveDataDirectory() then
        logBridgeTransport("[IsaacRanked][DBG] bridge transport=file")
        return sendBridgeRequestViaFile(message)
    end

    if getSocketModule() then
        logBridgeTransport("[IsaacRanked][DBG] bridge transport=http")
        return sendBridgeRequestViaHttp(message)
    end

    if isIoAvailable() and Config.getBridgeDir() then
        logBridgeTransport("[IsaacRanked][DBG] bridge transport=io-file")
        local ok, err = sendBridgeRequestViaIoFile(message)
        if ok then
            return true, nil
        end
        -- #region agent log
        Isaac.DebugString("[IsaacRanked][DBG] io-file bridge failed: " .. tostring(err))
        -- #endregion
    end

    logBridgeTransport("[IsaacRanked][DBG] bridge transport=log"
        .. " io=" .. tostring(isIoAvailable()))
    return sendBridgeRequestViaLog(message)
end

local function checkConnectionTimeout()
    if not Network._connectionDeadline then
        return
    end

    if Network._tickFrame < Network._connectionDeadline then
        return
    end

    if Network._awaitingHelloAck or Network._awaitingQueueUpdate then
        Network.resetConnectionAttempt()
        if State.current.matchState == State.MATCH_STATES.connecting
            or State.current.matchState == State.MATCH_STATES.queued then
            State.current.matchState = State.MATCH_STATES.idle
        end
        State.setError("Could not reach the matchmaking server. Please try again later.")
        State.setStatus("Connection failed")
        -- #region agent log
        Isaac.DebugString("[IsaacRanked][DBG] connection timeout waiting for server tick="
            .. tostring(Network._tickFrame))
        -- #endregion
    end
end

local MOCK_PACE_TIERS = {
    { minMs = 130000, advanceChance = 0.07, maxAhead = 1 },
    { minMs = 105000, advanceChance = 0.09, maxAhead = 2 },
    { minMs = 85000, advanceChance = 0.11, maxAhead = 2 },
}

local function getPlayerStageSnapshot()
    local stage = LevelStage.STAGE1_1
    local stageType = StageType.STAGETYPE_ORIGINAL
    local game = Game and Game()
    if game then
        local level = game:GetLevel()
        if level then
            stage = level:GetStage()
            stageType = level:GetStageType()
        elseif State.current.currentStage then
            stage = State.current.currentStage
            stageType = State.current.currentStageType or stageType
        end
    elseif State.current.currentStage then
        stage = State.current.currentStage
        stageType = State.current.currentStageType or stageType
    end
    return stage, stageType
end

local function resetMockOpponent()
    local stage, stageType = getPlayerStageSnapshot()
    Network._mockOpponent = {
        stage = stage,
        stageType = stageType,
        alive = true,
        lastAdvanceElapsedMs = 0,
        pace = MOCK_PACE_TIERS[math.random(1, #MOCK_PACE_TIERS)],
    }
end

local function advanceMockOpponent(playerEvent)
    if not Network._mockOpponent then
        resetMockOpponent()
    end

    local mock = Network._mockOpponent
    local pace = mock.pace or MOCK_PACE_TIERS[2]
    local playerStage = playerEvent.stage or LevelStage.STAGE1_1
    local playerStageType = playerEvent.stageType
    local playerElapsed = playerEvent.elapsedMs or 0

    if playerStageType ~= nil then
        if mock.stage == playerStage then
            mock.stageType = playerStageType
        elseif mock.stage < playerStage then
            mock.stage = playerStage
            mock.stageType = playerStageType
        end
    end

    local maxAllowed = playerStage + pace.maxAhead
    local minAllowed = math.max(LevelStage.STAGE1_1, playerStage - 3)

    if mock.stage > maxAllowed then
        mock.stage = maxAllowed
    end
    if mock.stage < minAllowed then
        mock.stage = minAllowed
    end

    local msSinceAdvance = playerElapsed - (mock.lastAdvanceElapsedMs or 0)
    if msSinceAdvance >= pace.minMs and mock.stage < maxAllowed then
        local floorsBehind = playerStage - mock.stage
        local chance = pace.advanceChance
        if floorsBehind >= 2 then
            chance = chance * 1.8
        elseif floorsBehind == 1 then
            chance = chance * 1.25
        elseif floorsBehind <= 0 then
            chance = chance * 0.4
        end

        if math.random() < chance then
            mock.stage = mock.stage + 1
            mock.lastAdvanceElapsedMs = playerElapsed
            if playerEvent.stageType ~= nil then
                mock.stageType = playerEvent.stageType
            end
        end
    end

    if playerEvent.alive == false then
        mock.alive = false
    end

    return {
        matchId = playerEvent.matchId,
        floor = mock.stage,
        stage = mock.stage,
        stageType = mock.stageType,
        elapsedMs = math.max(0, playerElapsed - math.random(30000, 90000)),
        alive = mock.alive,
    }
end

function Network.getMockOpponentProgress()
    return Network._mockOpponent
end

local function send(message)
    -- #region agent log
    Isaac.DebugString("[IsaacRanked][H2] send() type=" .. tostring(message and message.type)
        .. " mockMode=" .. tostring(State.current.mockMode)
        .. " MOCK_MODE=" .. tostring(Config.MOCK_MODE)
        .. " stateId=" .. tostring(State))
    -- #endregion

    if Config.MOCK_MODE or State.current.mockMode then
        Network.handleMockMessage(message)
        return true
    end

    local ok, err = sendBridgeRequest(message)

    -- #region agent log
    Isaac.DebugString("[IsaacRanked][DBG] bridge send ok=" .. tostring(ok)
        .. " err=" .. tostring(err))
    -- #endregion

    if not ok then
        State.setError(err or "network error")
        return false
    end
    return true
end

function Network.tick()
    Network._tickFrame = Network._tickFrame + 1

    -- #region agent log
    if not loggedStateShape then
        loggedStateShape = true
        Isaac.DebugString("[IsaacRanked] Network state shape type="
            .. tostring(type(State))
            .. " setError=" .. tostring(type(State.setError))
            .. " setStatus=" .. tostring(type(State.setStatus)))
    end
    -- #endregion

    local ok, err = pcall(function()
        pollBridgeResponses()
        checkConnectionTimeout()
        Network.processInbound()
    end)

    if not ok then
        State.setError("Network error: " .. tostring(err))
    end
end

function Network.hello()
    return send({
        type = "hello",
        protocolVersion = Config.PROTOCOL_VERSION,
        playerId = Config.getPlayerId(),
        displayName = Config.getDisplayName(),
        clientVersion = Config.CLIENT_VERSION,
        repentogonVersion = "repentogon",
    })
end

function Network.queueJoin(unlockedCharacters)
    return send({
        type = "queue_join",
        playerId = Config.getPlayerId(),
        unlockedCharacters = unlockedCharacters,
    })
end

function Network.startQueueJoin(unlockedCharacters)
    loggedInboxIncludeDiag = false
    Network.resetConnectionAttempt()
    Network._awaitingHelloAck = true
    Network._awaitingQueueUpdate = false
    Network._pendingQueueJoin = true
    Network._connectionDeadline = Network._tickFrame + CONNECTION_TIMEOUT_TICKS
    Network._pendingUnlockedCharacters = unlockedCharacters
    return Network.hello()
end

function Network.isServerConnected()
    return Network._serverConnected == true
end

function Network.resetConnectionAttempt()
    Network._awaitingHelloAck = false
    Network._awaitingQueueUpdate = false
    Network._pendingQueueJoin = false
    Network._connectionDeadline = nil
    Network._serverConnected = false
    for requestId, _ in pairs(pendingResponses) do
        pendingResponses[requestId] = nil
    end
end

function Network.queueLeave()
    return send({
        type = "queue_leave",
        playerId = Config.getPlayerId(),
    })
end

function Network.sendMatchStarted(matchId, actualSeed, actualPlayerType, integrity)
    return send({
        type = "match_started",
        matchId = matchId,
        playerId = Config.getPlayerId(),
        actualSeed = actualSeed,
        actualPlayerType = actualPlayerType,
        integrity = integrity,
    })
end

function Network.sendProgress(event)
    return send({
        type = "progress_event",
        playerId = Config.getPlayerId(),
        event = event,
    })
end

function Network.sendMatchResult(payload)
    return send({
        type = "match_result",
        playerId = Config.getPlayerId(),
        payload = payload,
    })
end

function Network.sendForfeit(matchId, reason)
    return send({
        type = "forfeit",
        playerId = Config.getPlayerId(),
        matchId = matchId,
        reason = reason,
    })
end

function Network.sendHeartbeat()
    return send({
        type = "heartbeat",
        playerId = Config.getPlayerId(),
        matchId = State.current.matchConfig and State.current.matchConfig.matchId,
        matchState = State.current.matchState,
    })
end

function Network.sendIntegrityViolation(report)
    return send({
        type = "integrity_violation",
        playerId = Config.getPlayerId(),
        report = report,
    })
end

function Network.processInbound()
    while #Network._inbox > 0 do
        local msg = table.remove(Network._inbox, 1)
        Network.handleServerMessage(msg)
    end
end

function Network.handleServerMessage(msg)
    if msg.type == "hello_ack" and msg.player then
        Network._serverConnected = true
        Network._awaitingHelloAck = false
        State.current.playerId = msg.player.playerId
        State.current.displayName = msg.player.displayName
        State.current.rating = msg.player.rating
        State.current.placementMatchesRemaining = msg.player.placementMatchesRemaining
        State.setStatus("Connected as " .. msg.player.displayName)
        State.setError("")
        if Network._pendingQueueJoin then
            Network._pendingQueueJoin = false
            Network.queueJoin(Network._pendingUnlockedCharacters)
            Network._awaitingQueueUpdate = true
            State.setStatus("Joining ranked queue...")
        end
    elseif msg.type == "queue_update" then
        State.current.queuePosition = msg.position or 0
        State.current.estimatedWaitSec = msg.estimatedWaitSec or 0
        State.current.rating = msg.rating or State.current.rating
        if msg.position and msg.position > 0 then
            Network._awaitingQueueUpdate = false
            Network._connectionDeadline = nil
            State.current.matchState = State.MATCH_STATES.queued
            State.setStatus("Searching... position " .. tostring(msg.position))
        elseif State.current.matchState == State.MATCH_STATES.queued
            or State.current.matchState == State.MATCH_STATES.connecting then
            State.current.matchState = State.MATCH_STATES.idle
            State.setStatus("Left queue")
        end
    elseif msg.type == "match_found" and msg.config then
        Match = Match or _G._IsaacRanked_Match
        local applied = Match.applyMatchConfig(msg.config)
        if not applied then
            return
        end
        local started = Match.startRankedRun()
        if not started and State.current.errorMessage == "" then
            State.setError("Match found but failed to start run.")
        end
    elseif msg.type == "opponent_progress" then
        State.current.opponentProgress = msg.event
    elseif msg.type == "match_resolved" then
        local Results = _G._IsaacRanked_Results
        if Results and Results.applyServerResolution then
            Results.applyServerResolution(msg)
        else
            State.current.rating = msg.newRating or State.current.rating
            State.setStatus(string.format("Match resolved (%s, %+d Elo)", msg.result or "?", msg.ratingDelta or 0))
            local Integrity = _G._IsaacRanked_Integrity
            if Integrity then Integrity.endRunProtection() end
            State.saveActiveMatch()
        end
    elseif msg.type == "error" then
        Network._awaitingHelloAck = false
        Network._awaitingQueueUpdate = false
        Network._pendingQueueJoin = false
        Network._connectionDeadline = nil
        if State.current.matchState == State.MATCH_STATES.connecting then
            State.current.matchState = State.MATCH_STATES.idle
        end
        State.setError(msg.message or "Server error")
    end
end

function Network.handleMockMessage(message)
    if message.type == "hello" then
        table.insert(Network._inbox, {
            type = "hello_ack",
            player = {
                playerId = Config.getPlayerId(),
                displayName = Config.getDisplayName(),
                rating = 1000,
                placementMatchesRemaining = 5,
            },
        })
    elseif message.type == "queue_join" then
        table.insert(Network._inbox, {
            type = "queue_update",
            position = 1,
            estimatedWaitSec = 2,
            rating = 1000,
        })
        Match = Match or _G._IsaacRanked_Match
        table.insert(Network._inbox, {
            type = "match_found",
            config = Match.buildMockConfig(),
        })
    elseif message.type == "queue_leave" then
        table.insert(Network._inbox, {
            type = "queue_update",
            position = 0,
            estimatedWaitSec = 0,
            rating = 1000,
        })
    elseif message.type == "match_result" then
        local payload = message.payload or {}
        table.insert(Network._inbox, {
            type = "match_resolved",
            result = payload.result or "win",
            newRating = 1000,
            ratingDelta = 0,
        })
        Network._mockOpponent = nil
    elseif message.type == "match_started" then
        resetMockOpponent()
    elseif message.type == "integrity_violation" or message.type == "forfeit" then
        table.insert(Network._inbox, {
            type = "match_resolved",
            matchId = message.matchId or (State.current.matchConfig and State.current.matchConfig.matchId),
            result = "loss",
            ratingDelta = 0,
            newRating = State.current.rating or 1000,
            reason = message.reason or (message.report and message.report.violationReason) or "integrity_violation",
        })
    elseif message.type == "progress_event" and message.event then
        table.insert(Network._inbox, {
            type = "opponent_progress",
            matchId = message.event.matchId,
            event = advanceMockOpponent(message.event),
        })
    end
end

_G._IsaacRanked_Network = Network
return Network
