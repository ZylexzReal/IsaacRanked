if _G._IsaacRanked_Objective then return _G._IsaacRanked_Objective end

local State = include("scripts.state")

local Objective = {}

-- Stage/type constants (for readability; mirrors the engine enums)
local S = {
    BASEMENT_1  = LevelStage.STAGE1_1,   -- 1
    BASEMENT_2  = LevelStage.STAGE1_2,   -- 2
    CAVES_1     = LevelStage.STAGE2_1,   -- 3
    CAVES_2     = LevelStage.STAGE2_2,   -- 4
    DEPTHS_1    = LevelStage.STAGE3_1,   -- 5
    DEPTHS_2    = LevelStage.STAGE3_2,   -- 6
    WOMB_1      = LevelStage.STAGE4_1,   -- 7
    WOMB_2      = LevelStage.STAGE4_2,   -- 8
    BLUE_WOMB   = LevelStage.STAGE4_3,   -- 9
    CATHEDRAL   = LevelStage.STAGE5,     -- 10  (stageType 1)
    SHEOL       = LevelStage.STAGE5,     -- 10  (stageType 0)
    CHEST       = LevelStage.STAGE6,     -- 11  (stageType 1)
    DARK_ROOM   = LevelStage.STAGE6,     -- 11  (stageType 0)
    VOID        = LevelStage.STAGE7,     -- 12
    HOME        = LevelStage.STAGE8,     -- 13
}

local T = {
    ORIGINAL    = StageType.STAGETYPE_ORIGINAL,     -- 0
    WOTL        = StageType.STAGETYPE_WOTL,         -- 1
    AFTERBIRTH  = StageType.STAGETYPE_AFTERBIRTH,    -- 2
    REPENTANCE  = StageType.STAGETYPE_REPENTANCE,    -- 4
    REPENTANCE_B = StageType.STAGETYPE_REPENTANCE_B, -- 5
}

--[[
    Each objective defines:
      id           - unique key
      name         - display name for the HUD
      bossName     - the final boss to defeat
      finalStage   - the LevelStage where the boss lives
      finalType    - the StageType of that stage (nil = any)
      maxStage     - maximum LevelStage the player should ever reach
      allowedStages - table of {stage, stageType} pairs the player is allowed
                      to transition TO.  nil = allow normal progression up to maxStage.
      overrides    - table keyed by "stage:type" that maps attempted transitions
                     to forced {stage, type} pairs. Used to enforce path at forks.
]]
Objective.OBJECTIVES = {
    {
        id = "mom",
        name = "Defeat Mom",
        bossName = "Mom",
        finalStage = S.DEPTHS_2,
        maxStage = S.DEPTHS_2,
    },
    {
        id = "moms_heart",
        name = "Defeat Mom's Heart",
        bossName = "Mom's Heart",
        finalStage = S.WOMB_2,
        maxStage = S.WOMB_2,
    },
    {
        id = "isaac",
        name = "Defeat Isaac",
        bossName = "Isaac",
        finalStage = S.CATHEDRAL,
        finalType = T.WOTL,
        maxStage = S.CATHEDRAL,
        overrides = {
            -- After Womb II, force Cathedral (stageType 1) instead of Sheol
            [S.SHEOL .. ":" .. T.ORIGINAL] = { S.CATHEDRAL, T.WOTL },
        },
    },
    {
        id = "satan",
        name = "Defeat Satan",
        bossName = "Satan",
        finalStage = S.SHEOL,
        finalType = T.ORIGINAL,
        maxStage = S.SHEOL,
        overrides = {
            -- After Womb II, force Sheol (stageType 0) instead of Cathedral
            [S.CATHEDRAL .. ":" .. T.WOTL] = { S.SHEOL, T.ORIGINAL },
        },
    },
    {
        id = "blue_baby",
        name = "Defeat ???",
        bossName = "??? (Blue Baby)",
        finalStage = S.CHEST,
        finalType = T.WOTL,
        maxStage = S.CHEST,
        overrides = {
            [S.SHEOL .. ":" .. T.ORIGINAL] = { S.CATHEDRAL, T.WOTL },
            [S.DARK_ROOM .. ":" .. T.ORIGINAL] = { S.CHEST, T.WOTL },
        },
    },
    {
        id = "the_lamb",
        name = "Defeat The Lamb",
        bossName = "The Lamb",
        finalStage = S.DARK_ROOM,
        finalType = T.ORIGINAL,
        maxStage = S.DARK_ROOM,
        overrides = {
            [S.CATHEDRAL .. ":" .. T.WOTL] = { S.SHEOL, T.ORIGINAL },
            [S.CHEST .. ":" .. T.WOTL] = { S.DARK_ROOM, T.ORIGINAL },
        },
    },
    {
        id = "hush",
        name = "Defeat Hush",
        bossName = "Hush",
        finalStage = S.BLUE_WOMB,
        maxStage = S.BLUE_WOMB,
        overrides = {
            -- After Womb II the game may try Cathedral or Sheol; force Blue Womb
            [S.CATHEDRAL .. ":" .. T.WOTL] = { S.BLUE_WOMB, T.ORIGINAL },
            [S.SHEOL .. ":" .. T.ORIGINAL] = { S.BLUE_WOMB, T.ORIGINAL },
        },
    },
    {
        id = "delirium",
        name = "Defeat Delirium",
        bossName = "Delirium",
        finalStage = S.VOID,
        maxStage = S.VOID,
        overrides = {
            -- After Womb II, go to Blue Womb first, then Void
            [S.CATHEDRAL .. ":" .. T.WOTL] = { S.BLUE_WOMB, T.ORIGINAL },
            [S.SHEOL .. ":" .. T.ORIGINAL] = { S.BLUE_WOMB, T.ORIGINAL },
            -- After Blue Womb / Hush, go to Void
            [S.CATHEDRAL .. ":" .. T.WOTL] = { S.BLUE_WOMB, T.ORIGINAL },
            [S.CHEST .. ":" .. T.WOTL] = { S.VOID, T.ORIGINAL },
            [S.DARK_ROOM .. ":" .. T.ORIGINAL] = { S.VOID, T.ORIGINAL },
        },
    },
    {
        id = "mother",
        name = "Defeat Mother",
        bossName = "Mother",
        finalStage = S.WOMB_2,
        finalType = T.REPENTANCE,
        maxStage = S.WOMB_2,
        forceAltPath = true,
    },
    {
        id = "the_beast",
        name = "Defeat The Beast",
        bossName = "The Beast",
        finalStage = S.HOME,
        maxStage = S.HOME,
        forceAltPath = true,
    },
}

function Objective.pickRandom(rng)
    local count = #Objective.OBJECTIVES
    local index
    if rng then
        index = (rng % count) + 1
    else
        index = math.random(1, count)
    end
    return Objective.OBJECTIVES[index]
end

function Objective.getActive()
    return State.current.objective
end

function Objective.setActive(obj)
    State.current.objective = obj
end

function Objective.clear()
    State.current.objective = nil
end

function Objective.onPreLevelSelect(stage, stageType)
    local obj = Objective.getActive()
    if not obj then
        return
    end

    -- Block progression past the final stage
    if stage > obj.maxStage then
        Isaac.DebugString("[IsaacRanked] Objective: blocked stage " .. tostring(stage)
            .. " (max " .. tostring(obj.maxStage) .. "), staying at " .. tostring(obj.finalStage))
        local forcedType = obj.finalType or stageType
        return { obj.finalStage, forcedType }
    end

    -- Apply path overrides at fork points
    if obj.overrides then
        local key = tostring(stage) .. ":" .. tostring(stageType)
        local override = obj.overrides[key]
        if override then
            Isaac.DebugString("[IsaacRanked] Objective: override " .. key
                .. " -> " .. tostring(override[1]) .. ":" .. tostring(override[2]))
            return { override[1], override[2] }
        end
    end

    -- For alt-path objectives (Mother, Beast), force Repentance stage types
    if obj.forceAltPath and stage <= S.WOMB_2 then
        if stageType ~= T.REPENTANCE and stageType ~= T.REPENTANCE_B then
            local altType = T.REPENTANCE
            Isaac.DebugString("[IsaacRanked] Objective: forcing alt path type "
                .. tostring(altType) .. " for stage " .. tostring(stage))
            return { stage, altType }
        end
    end

    return nil
end

local hudFont = nil
local COLOR_HUD = KColor(1, 0.9, 0.6, 0.9)
local COLOR_HUD_DIM = KColor(0.8, 0.75, 0.6, 0.7)

local function getHudFont()
    if hudFont == nil then
        hudFont = Font()
        hudFont:Load("font/pftempestasevencondensed.fnt")
    end
    return hudFont
end

function Objective.renderHUD()
    local obj = Objective.getActive()
    if not obj then
        return
    end

    if not State.isActiveMatch() and State.current.matchState ~= "starting" then
        return
    end

    local font = getHudFont()
    local text = "Objective: " .. obj.name
    local scale = 0.85
    local textWidth = font:GetStringWidthUTF8(text) * scale
    local screenWidth = Isaac.GetScreenWidth and Isaac.GetScreenWidth() or 480
    local x = screenWidth - textWidth - 8
    local y = 4

    font:DrawStringScaled(text, x, y, scale, scale, COLOR_HUD, 0, false)
end

_G._IsaacRanked_Objective = Objective
return Objective
