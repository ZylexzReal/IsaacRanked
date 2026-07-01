if _G._IsaacRanked_ModWhitelist then return _G._IsaacRanked_ModWhitelist end

local Config = include("scripts.config")
local DebugLog = include("scripts.debug_log")

local ModWhitelist = {}
ModWhitelist.VERSION = 3

-- Keep in sync with shared/modWhitelist.ts
ModWhitelist.ENTRIES = {
    { id = "isaac-ranked", name = "Isaac Ranked", match = "exact" },
    { id = "836319872", name = "External Item Descriptions", match = "suffix" },
}

local cachedEnabledMods = nil
local lastScanSource = nil

local function normalizePath(path)
    if type(path) ~= "string" then
        return ""
    end
    return path:lower():gsub("^@", ""):gsub("\\", "/")
end

local function folderMatchesEntry(folder, entry)
    if entry.match == "exact" then
        return folder == entry.id
    end
    if entry.match == "suffix" then
        return folder == entry.id or folder:sub(-#("_" .. entry.id)) == "_" .. entry.id
    end
    if entry.match == "contains" then
        return folder:find(entry.id, 1, true) ~= nil
    end
    return false
end

function ModWhitelist.isFolderWhitelisted(folder)
    for _, entry in ipairs(ModWhitelist.ENTRIES) do
        if folderMatchesEntry(folder, entry) then
            return true
        end
    end
    return false
end

local function extractModFolderFromPath(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end

    local normalized = normalizePath(path)
    local folder = normalized:match("/mods/([^/]+)/main%.lua$")
        or normalized:match("^mods/([^/]+)/main%.lua$")
        or normalized:match("/mods/([^/]+)/content/?$")
        or normalized:match("^mods/([^/]+)/content/?$")
        or normalized:match("/mods/([^/]+)/")
        or normalized:match("^mods/([^/]+)/")
        or normalized:match("/mods/([^/]+)$")
        or normalized:match("^mods/([^/]+)$")
    if folder and folder ~= "" then
        return folder
    end

    local moddingRoot = Config.getModdingRoot()
    if moddingRoot and moddingRoot ~= "" then
        local prefix = normalizePath(moddingRoot) .. "/"
        if normalized:sub(1, #prefix) == prefix then
            local remainder = normalized:sub(#prefix + 1)
            folder = remainder:match("^([^/]+)")
            if folder and folder ~= "" then
                return folder
            end
        end
    end

    return nil
end

local function addFolderFromPath(path, mods, seen)
    local folder = extractModFolderFromPath(path)
    if folder and not seen[folder] then
        seen[folder] = true
        table.insert(mods, folder)
        return true
    end
    return false
end

local function looksLikeModReference(value)
    return type(value) == "table"
        and type(value.AddCallback) == "function"
        and type(value.Name) == "string"
end

local function tryAddModReference(modRef, mods, seen)
    if not looksLikeModReference(modRef) then
        return false
    end

    local folder = nil
    if type(modRef.Path) == "string" and modRef.Path ~= "" then
        folder = extractModFolderFromPath(modRef.Path)
    end

    if type(Isaac) == "table" and type(Isaac.GetModId) == "function" then
        local ok, modId = pcall(Isaac.GetModId, modRef)
        if ok and type(modId) == "string" and modId ~= "" then
            if modId == "isaac-ranked" then
                folder = "isaac-ranked"
            elseif modId:match("^%d+$") then
                local suffix = "_" .. modId
                if folder and folder:sub(-#suffix) ~= suffix then
                    folder = modId
                end
            elseif not folder or folder == "" then
                folder = modId
            end
        end
    end

    if folder and not seen[folder] then
        seen[folder] = true
        table.insert(mods, folder)
        return true
    end

    return false
end

-- Enabled mods call RegisterMod in main.lua; their ModReference tables live in _G (e.g. EID).
function ModWhitelist.scanFromActiveModReferences()
    local mods = {}
    local seen = {}

    tryAddModReference(Config.mod, mods, seen)

    if type(_G) == "table" then
        for _, value in pairs(_G) do
            if looksLikeModReference(value) then
                tryAddModReference(value, mods, seen)
            end
        end
    end

    if #mods == 0 then
        return nil
    end

    table.sort(mods)
    return mods
end

-- Only enabled mods execute main.lua (disabled mods load content/ only).
function ModWhitelist.scanFromListLoadedMainLua()
    if not Debug or type(Debug.ListLoadedFiles) ~= "function" then
        return nil
    end

    local ok, files = pcall(Debug.ListLoadedFiles)
    if not ok or type(files) ~= "table" then
        return nil
    end

    local mods = {}
    local seen = {}
    for _, path in pairs(files) do
        if type(path) == "string" then
            local normalized = normalizePath(path)
            local folder = normalized:match("/mods/([^/]+)/main%.lua$")
                or normalized:match("^mods/([^/]+)/main%.lua$")
            if folder and not seen[folder] then
                seen[folder] = true
                table.insert(mods, folder)
            end
        end
    end

    if #mods == 0 then
        return nil
    end

    table.sort(mods)
    return mods
end

function ModWhitelist.scanFromPreflightFile()
    local ok, snapshot = pcall(include, "scripts.enabled_mods_preflight")
    if not ok or type(snapshot) ~= "table" or type(snapshot.enabledMods) ~= "table" then
        return nil
    end

    local mods = {}
    local seen = {}
    for _, folder in ipairs(snapshot.enabledMods) do
        if type(folder) == "string" and folder ~= "" and not seen[folder] then
            seen[folder] = true
            table.insert(mods, folder)
        end
    end

    if #mods == 0 then
        return nil
    end

    table.sort(mods)
    return mods
end

local function extractLastEnabledModsBlock(content)
    if type(content) ~= "string" or content == "" then
        return nil
    end

    local lastStart = nil
    local searchPos = 1
    while true do
        local found = content:find("Enabled Mods START", searchPos, true)
        if not found then
            break
        end
        lastStart = found
        searchPos = found + 1
    end

    if not lastStart then
        return nil
    end

    local blockStart = content:find("\n", lastStart, true)
    if not blockStart then
        return nil
    end
    blockStart = blockStart + 1

    local blockEnd = content:find("Enabled Mods END", blockStart, true)
    if not blockEnd then
        return nil
    end

    return content:sub(blockStart, blockEnd - 1)
end

function ModWhitelist.scanFromEnabledModsLog()
    local content = nil
    if type(Config.readDocumentsTextFile) == "function" then
        content = Config.readDocumentsTextFile("log.txt")
    end

    if not content then
        return nil
    end

    local lastBlock = extractLastEnabledModsBlock(content)
    if not lastBlock then
        return nil
    end

    local mods = {}
    for line in lastBlock:gmatch("[^\r\n]+") do
        local folder = line:match("^%s*(.-)%s*$")
        if folder and folder ~= ""
            and not folder:find("Enabled Mods", 1, true)
            and not folder:find("^%[INFO%]") then
            table.insert(mods, folder)
        end
    end

    if #mods == 0 then
        return nil
    end

    table.sort(mods)
    return mods
end

local function logScanResult(source, mods, extra)
    lastScanSource = source
    -- #region agent log
    Isaac.DebugString("[IsaacRanked][DBG] mod scan via " .. tostring(source)
        .. " count=" .. tostring(mods and #mods or 0)
        .. " mods=" .. table.concat(mods or {}, ", "))
    DebugLog.write("H5", "mod_whitelist.lua:scan", "mod scan result", {
        runId = "mod-scan",
        source = source,
        count = mods and #mods or 0,
        mods = mods,
        extra = extra or {},
    })
    -- #endregion
end

local function logScanFailure(extra)
    -- #region agent log
    Isaac.DebugString("[IsaacRanked][DBG] mod scan failed"
        .. " modPath=" .. tostring(extra and extra.modPath)
        .. " hasEID=" .. tostring(extra and extra.hasEID)
        .. " hasGetModId=" .. tostring(extra and extra.hasGetModId)
        .. " hasListLoaded=" .. tostring(extra and extra.hasListLoaded))
    DebugLog.write("H5", "mod_whitelist.lua:scan", "mod scan failed", {
        runId = "mod-scan",
        extra = extra or {},
    })
    -- #endregion
end

local function tryScan(source, scanner, extra)
    local mods = scanner()
    if mods and #mods > 0 then
        cachedEnabledMods = mods
        logScanResult(source, mods, extra)
        return mods
    end
    return nil
end

function ModWhitelist.scanEnabledModFolders()
    if cachedEnabledMods and #cachedEnabledMods > 0 then
        return cachedEnabledMods
    end

    local debugExtra = {
        modPath = Config.mod and Config.mod.Path or nil,
        hasEID = _G.EID ~= nil,
        hasGetModId = type(Isaac) == "table" and type(Isaac.GetModId) == "function",
        hasListLoaded = Debug ~= nil and type(Debug.ListLoadedFiles) == "function",
        documentsRoot = Config.getDocumentsRoot(),
        moddingRoot = Config.getModdingRoot(),
    }

    local fromRefs = tryScan("active_mod_references", ModWhitelist.scanFromActiveModReferences, debugExtra)
    if fromRefs then
        return fromRefs
    end

    local fromMainLua = tryScan("ListLoadedFiles.main_lua", ModWhitelist.scanFromListLoadedMainLua, debugExtra)
    if fromMainLua then
        return fromMainLua
    end

    local fromPreflight = tryScan("enabled_mods_preflight", ModWhitelist.scanFromPreflightFile, debugExtra)
    if fromPreflight then
        return fromPreflight
    end

    local fromLog = tryScan("log.txt", ModWhitelist.scanFromEnabledModsLog, debugExtra)
    if fromLog then
        return fromLog
    end

    cachedEnabledMods = nil
    logScanFailure(debugExtra)
    return nil
end

function ModWhitelist.captureAtStartup()
    ModWhitelist.clearCache()
    ModWhitelist.scanEnabledModFolders()
end

function ModWhitelist.getLastScanSource()
    return lastScanSource
end

function ModWhitelist.validateFolders(enabledMods)
    local disallowed = {}
    if type(enabledMods) ~= "table" then
        return false, disallowed
    end

    for _, folder in ipairs(enabledMods) do
        if not ModWhitelist.isFolderWhitelisted(folder) then
            table.insert(disallowed, folder)
        end
    end

    table.sort(disallowed)
    return #disallowed == 0, disallowed
end

function ModWhitelist.getStatus()
    ModWhitelist.clearCache()
    local enabledMods = ModWhitelist.scanEnabledModFolders()
    if not enabledMods then
        return nil, {}, false
    end

    local ok, disallowed = ModWhitelist.validateFolders(enabledMods)
    return enabledMods, disallowed, ok
end

function ModWhitelist.formatDisallowedList(disallowed)
    if type(disallowed) ~= "table" or #disallowed == 0 then
        return ""
    end
    return table.concat(disallowed, ", ")
end

function ModWhitelist.getWhitelistSummary()
    local names = {}
    for _, entry in ipairs(ModWhitelist.ENTRIES) do
        table.insert(names, entry.name)
    end
    return table.concat(names, ", ")
end

function ModWhitelist.clearCache()
    cachedEnabledMods = nil
    lastScanSource = nil
end

_G._IsaacRanked_ModWhitelist = ModWhitelist
return ModWhitelist
