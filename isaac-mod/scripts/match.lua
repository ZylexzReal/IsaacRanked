if _G._IsaacRanked_Match then return _G._IsaacRanked_Match end

local Config = include("scripts.config")
local State = include("scripts.state")
local Integrity = include("scripts.integrity")
local Objective = include("scripts.objective")
local Network -- resolved lazily to avoid circular include at load time

local Match = {}

local function reseedRandom()
    local frame = 0
    if Game then
        local ok, game = pcall(Game)
        if ok and game then
            frame = game:GetFrameCount()
        end
    end
    local time = (os and os.time) and os.time() or 0
    math.randomseed(time + frame)
end

local function randomSeed()
    local seed = math.random(1, 2147483647)
    if Seeds and Seeds.Seed2String then
        return seed, Seeds.Seed2String(seed)
    end
    return seed, tostring(seed)
end

local RANKED_CHARACTERS = {
    { type = PlayerType.PLAYER_ISAAC,           name = "Isaac" },
    { type = PlayerType.PLAYER_MAGDALENE,       name = "Magdalene" },
    { type = PlayerType.PLAYER_CAIN,            name = "Cain" },
    { type = PlayerType.PLAYER_JUDAS,           name = "Judas" },
    { type = PlayerType.PLAYER_EVE,             name = "Eve" },
    { type = PlayerType.PLAYER_SAMSON,          name = "Samson" },
    { type = PlayerType.PLAYER_AZAZEL,          name = "Azazel" },
    { type = PlayerType.PLAYER_EDEN,            name = "Eden" },
    { type = PlayerType.PLAYER_THELOST,         name = "The Lost" },
    { type = PlayerType.PLAYER_LILITH,          name = "Lilith" },
    { type = PlayerType.PLAYER_KEEPER,          name = "Keeper" },
    { type = PlayerType.PLAYER_BETHANY,         name = "Bethany" },
    { type = PlayerType.PLAYER_JACOB,           name = "Jacob" },
    { type = PlayerType.PLAYER_ISAAC_B,         name = "Tainted Isaac" },
    { type = PlayerType.PLAYER_MAGDALENE_B,     name = "Tainted Magdalene" },
    { type = PlayerType.PLAYER_CAIN_B,          name = "Tainted Cain" },
    { type = PlayerType.PLAYER_JUDAS_B,         name = "Tainted Judas" },
    { type = PlayerType.PLAYER_BLUEBABY_B,      name = "Tainted ???" },
    { type = PlayerType.PLAYER_EVE_B,           name = "Tainted Eve" },
    { type = PlayerType.PLAYER_SAMSON_B,        name = "Tainted Samson" },
    { type = PlayerType.PLAYER_AZAZEL_B,        name = "Tainted Azazel" },
    { type = PlayerType.PLAYER_LAZARUS_B,       name = "Tainted Lazarus" },
    { type = PlayerType.PLAYER_EDEN_B,          name = "Tainted Eden" },
    { type = PlayerType.PLAYER_THELOST_B,       name = "Tainted The Lost" },
    { type = PlayerType.PLAYER_LILITH_B,        name = "Tainted Lilith" },
    { type = PlayerType.PLAYER_KEEPER_B,        name = "Tainted Keeper" },
    { type = PlayerType.PLAYER_APOLLYON_B,      name = "Tainted Apollyon" },
    { type = PlayerType.PLAYER_THEFORGOTTEN_B,  name = "Tainted The Forgotten" },
    { type = PlayerType.PLAYER_BETHANY_B,       name = "Tainted Bethany" },
    { type = PlayerType.PLAYER_JACOB_B,         name = "Tainted Jacob" },
    { type = PlayerType.PLAYER_LAZARUS2_B,      name = "Tainted Lazarus II" },
    { type = PlayerType.PLAYER_JACOB2_B,        name = "Tainted Jacob & Esau" },
    { type = PlayerType.PLAYER_THESOUL_B,       name = "Tainted The Soul" },
}

function Match.buildMockConfig()
    reseedRandom()

    local seed, seedString = randomSeed()
    local pick = RANKED_CHARACTERS[math.random(1, #RANKED_CHARACTERS)]
    local obj = Objective.pickRandom()

    return {
        matchId = "mock-" .. tostring(math.random(1000, 9999)),
        seed = seed,
        seedString = seedString,
        playerType = pick.type,
        characterName = pick.name,
        difficulty = Difficulty.DIFFICULTY_HARD,
        rulesetVersion = Config.PROTOCOL_VERSION,
        objective = obj,
        opponent = {
            playerId = "mock-bot",
            displayName = "Mock Bot",
            rating = 1000,
        },
    }
end

local function hasRepentogonStart()
    return type(Isaac.StartNewGame) == "function"
end

function Match.validateConfig(config)
    if config == nil then
        return false, "missing match config"
    end
    if config.seed == nil or config.playerType == nil or config.matchId == nil then
        return false, "incomplete match config"
    end
    return true, nil
end

function Match.applyMatchConfig(config)
    local ok, err = Match.validateConfig(config)
    if not ok then
        State.setError(err)
        return false
    end

    State.current.matchConfig = config
    State.current.matchState = State.MATCH_STATES.matched

    if config.objective then
        Objective.setActive(config.objective)
        Isaac.DebugString("[IsaacRanked] Objective set: " .. config.objective.name)
    else
        local obj = Objective.pickRandom()
        Objective.setActive(obj)
        Isaac.DebugString("[IsaacRanked] Objective randomly assigned: " .. obj.name)
    end

    State.saveActiveMatch()
    State.setStatus("Match found vs " .. (config.opponent and config.opponent.displayName or "opponent"))
    return true
end

function Match.startRankedRun()
    -- Do not hard-block run start when options.ini cannot be verified.
    if not Integrity.canQueue(false) then
        return false
    end

    local config = State.current.matchConfig
    local ok, err = Match.validateConfig(config)
    if not ok then
        State.setError(err)
        return false
    end

    if not hasRepentogonStart() then
        State.setError("REPENTOGON is required for ranked run start.")
        return false
    end

    State.current.matchState = State.MATCH_STATES.starting
    Integrity.beginRunProtection()
    State.current.launchingRun = true

    local playerType = config.playerType
    local seed = config.seed
    local difficulty = config.difficulty or Difficulty.DIFFICULTY_HARD
    local challenge = Challenge.CHALLENGE_NULL
    local isCustomRun = true

    if CharacterMenu and CharacterMenu.SetSelectedCharacterID then
        local menuId = CharacterMenu.GetCharacterMenuIDFromPlayerType
            and CharacterMenu.GetCharacterMenuIDFromPlayerType(playerType)
        if menuId ~= nil then
            CharacterMenu.SetSelectedCharacterID(menuId)
        end
    end

    local started, startErr = pcall(function()
        Isaac.StartNewGame(playerType, challenge, difficulty, seed, isCustomRun)
    end)
    if not started then
        State.current.matchState = State.MATCH_STATES.matched
        State.current.launchingRun = false
        Integrity.endRunProtection()
        State.setError("Failed to start ranked run: " .. tostring(startErr))
        return false
    end

    State.setStatus("Starting ranked run...")
    return true
end

function Match.startMockRun()
    Match.applyMatchConfig(Match.buildMockConfig())
    return Match.startRankedRun()
end

function Match.onGameStarted()
    local config = State.current.matchConfig
    if config == nil then
        return
    end

    local game = Game()
    local seeds = game:GetSeeds()
    local actualSeed = seeds:GetStartSeed()
    local player = game:GetPlayer(0)
    local actualPlayerType = player:GetPlayerType()

    if actualSeed ~= config.seed then
        Integrity.flagViolation("seed mismatch")
        return
    end

    if actualPlayerType ~= config.playerType then
        Integrity.flagViolation("character mismatch")
        return
    end

    State.current.matchState = State.MATCH_STATES.in_progress
    State.current.runStartedAtFrame = game:GetFrameCount()

    Network = Network or _G._IsaacRanked_Network
    Network.sendMatchStarted(config.matchId, actualSeed, actualPlayerType, Integrity.buildReport(config.matchId))
end

function Match.getAssignedSeedString()
    local config = State.current.matchConfig
    if config and config.seedString then
        return config.seedString
    end
    if config and config.seed and Seeds and Seeds.Seed2String then
        return Seeds.Seed2String(config.seed)
    end
    return "--------"
end

function Match.returnToMainMenu()
    State.current.returningToMenu = true
    State.saveActiveMatch()

    -- #region agent log
    Isaac.DebugString("[IsaacRanked][H3] returnToMainMenu Fadeout="
        .. tostring(Game().Fadeout ~= nil)
        .. " FadeoutTarget=" .. tostring(FadeoutTarget ~= nil))
    -- #endregion

    local game = Game()
    if game and game.Fadeout and FadeoutTarget and FadeoutTarget.SAVEFILE_MENU then
        game:Fadeout(1.0, FadeoutTarget.SAVEFILE_MENU)
        return true
    end

    if game and game.End and Ending and Ending.ENDING_GAMEOVER then
        game:End(Ending.ENDING_GAMEOVER)
        return true
    end

    State.current.returningToMenu = false
    return false
end

_G._IsaacRanked_Match = Match
return Match
