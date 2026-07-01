if _G._IsaacRanked_DebugLog then return _G._IsaacRanked_DebugLog end

local json = include("scripts.json")

local DebugLog = {}

function DebugLog.write(hypothesisId, location, message, data)
    local payload = {
        sessionId = "f9e5f7",
        hypothesisId = hypothesisId,
        location = location,
        message = message,
        data = data or {},
        timestamp = ((os and os.time) and os.time() or 0) * 1000,
        runId = (data and data.runId) or "post-fix",
    }

    local encoded = json.encode(payload) .. "\n"
    local paths = { "D:/IsaacRanked/debug-f9e5f7.log" }
    local Config = _G._IsaacRanked_Config
    if Config and type(Config.getBridgeDir) == "function" then
        local bridgeDir = Config.getBridgeDir()
        if bridgeDir then
            table.insert(paths, bridgeDir .. "/debug-f9e5f7.log")
        end
    end

    for _, path in ipairs(paths) do
        pcall(function()
            local file = io.open(path, "a")
            if file then
                file:write(encoded)
                file:close()
            end
        end)
    end
end

_G._IsaacRanked_DebugLog = DebugLog
return DebugLog
