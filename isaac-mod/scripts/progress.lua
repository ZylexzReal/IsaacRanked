if _G._IsaacRanked_Progress then return _G._IsaacRanked_Progress end

local State = include("scripts.state")

local Progress = {}

local VANILLA_NAMES = {
    [LevelStage.STAGE1_1] = "Basement I",
    [LevelStage.STAGE1_2] = "Basement II",
    [LevelStage.STAGE2_1] = "Caves I",
    [LevelStage.STAGE2_2] = "Caves II",
    [LevelStage.STAGE3_1] = "Depths I",
    [LevelStage.STAGE3_2] = "Depths II",
    [LevelStage.STAGE4_1] = "Womb I",
    [LevelStage.STAGE4_2] = "Womb II",
}

local AFTERBIRTH_NAMES = {
    [LevelStage.STAGE1_1] = "Burning Basement I",
    [LevelStage.STAGE1_2] = "Burning Basement II",
    [LevelStage.STAGE2_1] = "Flooded Caves I",
    [LevelStage.STAGE2_2] = "Flooded Caves II",
    [LevelStage.STAGE3_1] = "Dank Depths I",
    [LevelStage.STAGE3_2] = "Dank Depths II",
    [LevelStage.STAGE4_1] = "Utero I",
    [LevelStage.STAGE4_2] = "Utero II",
}

local REPENTANCE_NAMES = {
    [LevelStage.STAGE1_1] = "Downpour I",
    [LevelStage.STAGE1_2] = "Downpour II",
    [LevelStage.STAGE2_1] = "Mines I",
    [LevelStage.STAGE2_2] = "Mines II",
    [LevelStage.STAGE3_1] = "Ashpit I",
    [LevelStage.STAGE3_2] = "Ashpit II",
    [LevelStage.STAGE4_1] = "Mausoleum I",
    [LevelStage.STAGE4_2] = "Mausoleum II",
}

local REPENTANCE_B_NAMES = {
    [LevelStage.STAGE1_1] = "Dross I",
    [LevelStage.STAGE1_2] = "Dross II",
    [LevelStage.STAGE2_1] = "Tainted Mines I",
    [LevelStage.STAGE2_2] = "Tainted Mines II",
    [LevelStage.STAGE3_1] = "Tainted Ashpit I",
    [LevelStage.STAGE3_2] = "Tainted Ashpit II",
    [LevelStage.STAGE4_1] = "Gehenna I",
    [LevelStage.STAGE4_2] = "Gehenna II",
}

local CELLAR_NAMES = {
    [LevelStage.STAGE1_1] = "Cellar I",
    [LevelStage.STAGE1_2] = "Cellar II",
}

function Progress.formatStageName(stage, stageType)
    stageType = stageType or StageType.STAGETYPE_ORIGINAL

    if stage == LevelStage.STAGE4_3 then
        return "Blue Womb"
    end
    if stage == LevelStage.STAGE7 then
        return "The Void"
    end
    if stage == LevelStage.STAGE8 then
        return "Home"
    end
    if stage == LevelStage.STAGE5 then
        if stageType == StageType.STAGETYPE_WOTL then
            return "Cathedral"
        elseif stageType == StageType.STAGETYPE_REPENTANCE then
            return "Mausoleum I"
        elseif stageType == StageType.STAGETYPE_REPENTANCE_B then
            return "Mausoleum II"
        end
        return "Sheol"
    end
    if stage == LevelStage.STAGE6 then
        if stageType == StageType.STAGETYPE_WOTL then
            return "Chest"
        elseif stageType == StageType.STAGETYPE_REPENTANCE then
            return "Gehenna I"
        elseif stageType == StageType.STAGETYPE_REPENTANCE_B then
            return "Gehenna II"
        end
        return "Dark Room"
    end

    if stageType == StageType.STAGETYPE_WOTL then
        if CELLAR_NAMES[stage] then
            return CELLAR_NAMES[stage]
        end
    end

    local names = VANILLA_NAMES
    if stageType == StageType.STAGETYPE_AFTERBIRTH then
        names = AFTERBIRTH_NAMES
    elseif stageType == StageType.STAGETYPE_REPENTANCE then
        names = REPENTANCE_NAMES
    elseif stageType == StageType.STAGETYPE_REPENTANCE_B then
        names = REPENTANCE_B_NAMES
    end

    return names[stage] or ("Floor " .. tostring(stage))
end

local hudFont = nil
local COLOR_SELF = KColor(0.55, 1, 0.65, 0.95)
local COLOR_OPP = KColor(1, 0.55, 0.45, 0.95)
local COLOR_OPP_DEAD = KColor(0.65, 0.55, 0.55, 0.75)
local COLOR_UNKNOWN = KColor(0.75, 0.75, 0.75, 0.7)

local HUD_SCALE = 0.8
local SCREEN_MARGIN = 8
local LINE_HEIGHT = 12

local function getHudFont()
    if hudFont == nil then
        hudFont = Font()
        hudFont:Load("font/pftempestasevencondensed.fnt")
    end
    return hudFont
end

local function getScreenWidth()
    if Isaac.GetScreenWidth then
        return Isaac.GetScreenWidth()
    end
    return 480
end

local function getScreenHeight()
    if Isaac.GetScreenHeight then
        return Isaac.GetScreenHeight()
    end
    return 270
end

local function progressStartY()
    -- Place text just below the minimap (top-right corner).
    return math.floor(getScreenHeight() * 0.21) + 4
end

local function maxTextWidth()
    return getScreenWidth() - (SCREEN_MARGIN * 2)
end

local function fitText(font, text, maxWidth)
    if font:GetStringWidthUTF8(text) * HUD_SCALE <= maxWidth then
        return text
    end
    local trimmed = text
    while #trimmed > 1 do
        trimmed = string.sub(trimmed, 1, -2)
        local candidate = trimmed .. "..."
        if font:GetStringWidthUTF8(candidate) * HUD_SCALE <= maxWidth then
            return candidate
        end
    end
    return "..."
end

local function drawRightAlignedLine(font, text, y, color)
    local maxWidth = maxTextWidth()
    local fitted = fitText(font, text, maxWidth)
    local textWidth = font:GetStringWidthUTF8(fitted) * HUD_SCALE
    local x = math.max(SCREEN_MARGIN, getScreenWidth() - textWidth - SCREEN_MARGIN)
    font:DrawStringScaled(fitted, x, y, HUD_SCALE, HUD_SCALE, color, 0, false)
end

local function getLocalStage()
    local game = Game()
    if game then
        local level = game:GetLevel()
        if level then
            return level:GetStage(), level:GetStageType()
        end
    end
    return State.current.currentStage or 1, State.current.currentStageType or StageType.STAGETYPE_ORIGINAL
end

local function getOpponentLabel()
    local config = State.current.matchConfig
    if config and config.opponent and config.opponent.displayName then
        return config.opponent.displayName
    end
    return "Opponent"
end

function Progress.renderHUD()
    if not State.isActiveMatch() and State.current.matchState ~= "starting" then
        return
    end
    if State.current.matchState == State.MATCH_STATES.finished then
        return
    end

    local font = getHudFont()
    local y = progressStartY()

    local selfStage, selfType = getLocalStage()
    local selfLine = "You: " .. Progress.formatStageName(selfStage, selfType)
    drawRightAlignedLine(font, selfLine, y, COLOR_SELF)

    y = y + LINE_HEIGHT

    local opp = State.current.opponentProgress
    local oppLine
    local oppColor = COLOR_OPP
    if opp then
        local oppName = getOpponentLabel()
        local stageName = Progress.formatStageName(opp.stage, opp.stageType)
        oppLine = oppName .. ": " .. stageName
        if opp.alive == false then
            oppLine = oppLine .. " (dead)"
            oppColor = COLOR_OPP_DEAD
        end
    else
        oppLine = getOpponentLabel() .. ": ..."
        oppColor = COLOR_UNKNOWN
    end

    drawRightAlignedLine(font, oppLine, y, oppColor)
end

_G._IsaacRanked_Progress = Progress
return Progress
