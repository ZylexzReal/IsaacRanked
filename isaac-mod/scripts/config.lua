if _G._IsaacRanked_Config then return _G._IsaacRanked_Config end

local Config = {}

Config.CLIENT_VERSION = "0.1.0"
Config.PROTOCOL_VERSION = 1
Config.MOCK_MODE = false
Config.WIN_CONDITION = "mom" -- mom | lamb | beast | run_end
Config.BRIDGE_SUBDIR = "isaac-ranked-bridge"

-- Use the official Isaac Ranked Launcher for remote matchmaking (Steam Workshop release).
-- Set to false only for local dev without the launcher (npm run dev on 127.0.0.1).
Config.USE_LAUNCHER_BRIDGE = true

-- Official matchmaking server hostname (display / future direct HTTP).
Config.MATCHMAKING_SERVER_HOST = "ranked.example.com"
Config.MATCHMAKING_SERVER_PORT = 8766

-- Active bridge target. Use 127.0.0.1 for local `npm run dev`.
-- For Workshop release, set this to the same value as MATCHMAKING_SERVER_HOST.
Config.BRIDGE_HTTP_HOST = "127.0.0.1"
Config.BRIDGE_HTTP_PORT = Config.MATCHMAKING_SERVER_PORT

Config.mod = nil
Config._documentsRoot = nil
Config._moddingRoot = nil
Config._memoryState = nil

local json = include("scripts.json")

function Config.init(mod)
    Config.mod = mod
    Config.loadMemoryState()
end

local function normalizePath(path)
    if path == nil or path == "" then
        return nil
    end
    return path:gsub("\\", "/"):gsub("/+$", "")
end

local function stripBom(text)
    if text == nil then
        return nil
    end
    return text:gsub("^\239\187\191", "")
end

local function readTextFile(path)
    if not path then
        return nil
    end

    local ok, content = pcall(function()
        local file = io.open(path, "r")
        if not file then
            return nil
        end
        local text = file:read("*a")
        file:close()
        return text
    end)

    if not ok then
        return nil
    end

    return stripBom(content)
end

local function getModScriptPath(filename)
    if Config.mod and type(Config.mod.Path) == "string" and Config.mod.Path ~= "" then
        return Config.mod.Path .. "/scripts/" .. filename
    end
    return "mods/isaac-ranked/scripts/" .. filename
end

local function getModScriptPathCandidates(filename)
    return {
        getModScriptPath(filename),
        "mods/isaac-ranked/scripts/" .. filename,
        "Mods/isaac-ranked/scripts/" .. filename,
        "scripts/" .. filename,
    }
end

local function getDirectoryRoot(getter)
    if type(Directory) ~= "table" or type(getter) ~= "function" then
        return nil
    end

    local ok, dir = pcall(getter)
    if not ok or not dir then
        return nil
    end

    for _, method in ipairs({ "path", "Path" }) do
        if type(dir[method]) == "function" then
            local okPath, path = pcall(dir[method], dir)
            if okPath and path and path ~= "" then
                return normalizePath(path)
            end
        end
    end

    return nil
end

local function readTextFromDirectoryRoot(getter, relativePath)
    if type(Directory) ~= "table" or type(getter) ~= "function" then
        return nil
    end

    local ok, dir = pcall(getter)
    if not ok or not dir then
        return nil
    end

    local file = nil
    for _, factory in ipairs({ "File", "Get" }) do
        if type(dir[factory]) == "function" then
            local okFile, resolved = pcall(dir[factory], dir, relativePath)
            if okFile and resolved then
                file = resolved
                break
            end
        end
    end

    if not file then
        return nil
    end

    for _, reader in ipairs({ "Read", "read", "ReadAll" }) do
        if type(file[reader]) == "function" then
            local okRead, content = pcall(file[reader], file)
            if okRead and content then
                return stripBom(content)
            end
        end
    end

    return nil
end

local function parseSavedataPathFile(content)
    if not content then
        return nil, nil
    end

    local savePath = content:match("Save Data Path:%s*([^\r\n]+)")
    local moddingPath = content:match("Modding Data Path:%s*([^\r\n]+)")
    if savePath or moddingPath then
        return normalizePath(savePath), normalizePath(moddingPath)
    end

    for line in string.gmatch(content, "[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed and trimmed:match("^[A-Za-z]:") then
            return normalizePath(trimmed), nil
        end
    end

    return nil, nil
end

local function readRepentogonPathFile()
    local candidates = {
        "Repentogon/savedatapath.txt",
        "repentogon/savedatapath.txt",
        "../Repentogon/savedatapath.txt",
        "savedatapath.txt",
        "../savedatapath.txt",
        "../../savedatapath.txt",
    }

    for _, candidate in ipairs(candidates) do
        local savePath, moddingPath = parseSavedataPathFile(readTextFile(candidate))
        if savePath or moddingPath then
            return savePath, moddingPath
        end
    end

    return nil, nil
end

local function readInstalledPathValues()
    local documentsRoot = nil
    local moddingRoot = nil

    for _, path in ipairs(getModScriptPathCandidates("paths.lua")) do
        local content = readTextFile(path)
        if content then
            local docs = content:match('documentsRoot%s*=%s*"([^"]+)"')
            local modding = content:match('moddingRoot%s*=%s*"([^"]+)"')
            if docs and docs ~= "" then
                documentsRoot = normalizePath(docs)
            end
            if modding and modding ~= "" then
                moddingRoot = normalizePath(modding)
            end
            if documentsRoot or moddingRoot then
                break
            end
        end
    end

    local ok, paths = pcall(include, "scripts.paths")
    if ok and type(paths) == "table" then
        if paths.documentsRoot and paths.documentsRoot ~= "" then
            documentsRoot = documentsRoot or normalizePath(paths.documentsRoot)
        end
        if paths.moddingRoot and paths.moddingRoot ~= "" then
            moddingRoot = moddingRoot or normalizePath(paths.moddingRoot)
        end
    end

    return documentsRoot, moddingRoot
end

local function inferModdingRootFromModPath()
    if Config.mod and type(Config.mod.Path) == "string" and Config.mod.Path ~= "" then
        local modPath = normalizePath(Config.mod.Path)
        local parent = modPath and modPath:match("^(.*)/[^/]+$")
        if parent and parent ~= "" then
            return parent
        end
    end
    return nil
end

function Config.getDocumentsRoot()
    if Config._documentsRoot then
        return Config._documentsRoot
    end

    local fromDirectory = getDirectoryRoot(Directory and Directory.savedata)
    if fromDirectory then
        Config._documentsRoot = fromDirectory
        return fromDirectory
    end

    if Config._memoryState and Config._memoryState.documentsRoot then
        Config._documentsRoot = Config._memoryState.documentsRoot
        return Config._documentsRoot
    end

    local installedDocs, _ = readInstalledPathValues()
    if installedDocs then
        Config._documentsRoot = installedDocs
        return installedDocs
    end

    local savePath, _ = readRepentogonPathFile()
    if savePath then
        Config._documentsRoot = savePath
        return savePath
    end

    return nil
end

function Config.getModdingRoot()
    if Config._moddingRoot then
        return Config._moddingRoot
    end

    local fromDirectory = getDirectoryRoot(Directory and Directory.modding)
    if fromDirectory then
        Config._moddingRoot = fromDirectory
        return fromDirectory
    end

    if Config._memoryState and Config._memoryState.moddingRoot then
        Config._moddingRoot = Config._memoryState.moddingRoot
        return Config._moddingRoot
    end

    local _, installedModding = readInstalledPathValues()
    if installedModding then
        Config._moddingRoot = installedModding
        return installedModding
    end

    local _, moddingPath = readRepentogonPathFile()
    if moddingPath then
        Config._moddingRoot = moddingPath
        return moddingPath
    end

    local inferred = inferModdingRootFromModPath()
    if inferred then
        Config._moddingRoot = inferred
        return inferred
    end

    return nil
end

function Config.getBridgeDir()
    local documentsRoot = Config.getDocumentsRoot()
    if documentsRoot then
        return documentsRoot .. "/" .. Config.BRIDGE_SUBDIR
    end

    if Config.mod and type(Config.mod.Path) == "string" and Config.mod.Path ~= "" then
        return Config.mod.Path .. "/bridge"
    end

    local moddingRoot = Config.getModdingRoot()
    if moddingRoot then
        return moddingRoot .. "/" .. Config.BRIDGE_SUBDIR
    end

    return nil
end

function Config.getOptionsIniPath()
    local root = Config.getDocumentsRoot()
    if not root then
        return nil
    end
    return root .. "/options.ini"
end

function Config.readDocumentsTextFile(relativePath)
    if not relativePath or relativePath == "" then
        return nil
    end

    local fromDirectory = readTextFromDirectoryRoot(Directory and Directory.savedata, relativePath)
    if fromDirectory then
        return fromDirectory
    end

    local root = Config.getDocumentsRoot()
    if not root then
        return nil
    end

    local normalized = relativePath:gsub("\\", "/"):gsub("^/+", "")
    return readTextFile(root .. "/" .. normalized)
end

local function parseIniFlag(content, key)
    if not content then
        return nil
    end

    for line in string.gmatch(content, "[^\r\n]+") do
        local stripped = line:gsub("^\239\187\191", "")
        local name, value = stripped:match("^%s*([%w_]+)%s*=%s*(%d+)%s*$")
        if name == key and value ~= nil then
            return value == "1"
        end
    end

    return nil
end

function Config.getOptionsIniPathCandidates()
    local root = Config.getDocumentsRoot()
    if not root then
        return {}
    end

    return {
        root .. "/options.ini",
        root:gsub("/", "\\") .. "\\options.ini",
    }
end

function Config.readEnableDebugConsoleFromOptions()
    local fromSaveData = parseIniFlag(readTextFromDirectoryRoot(Directory and Directory.savedata, "options.ini"), "EnableDebugConsole")
    if fromSaveData ~= nil then
        return fromSaveData
    end

    for _, path in ipairs(Config.getOptionsIniPathCandidates()) do
        local enabled = parseIniFlag(readTextFile(path), "EnableDebugConsole")
        if enabled ~= nil then
            return enabled
        end
    end

    return nil
end

local function parsePreflightConsoleState(content)
    if not content then
        return nil
    end
    if content:match("vanillaConsoleEnabled%s*=%s*true") then
        return true
    end
    if content:match("vanillaConsoleEnabled%s*=%s*false") then
        return false
    end
    return nil
end

function Config.readModConsoleSnapshot()
    local ok, preflight = pcall(include, "scripts.preflight")
    if ok and type(preflight) == "table" and preflight.vanillaConsoleEnabled ~= nil then
        return preflight.vanillaConsoleEnabled == true
    end

    for _, path in ipairs(getModScriptPathCandidates("console_state.txt")) do
        local content = readTextFile(path)
        if content then
            local value = content:match("^%s*(%d+)")
            if value ~= nil then
                return value == "1"
            end
        end
    end

    for _, path in ipairs(getModScriptPathCandidates("preflight.lua")) do
        local enabled = parsePreflightConsoleState(readTextFile(path))
        if enabled ~= nil then
            return enabled
        end
    end

    return nil
end

function Config.loadMemoryState()
    if not Config.mod then
        Config._memoryState = {}
        return Config._memoryState
    end

    local raw = Config.mod:LoadData()
    if raw == nil or raw == "" then
        Config._memoryState = {}
        return Config._memoryState
    end

    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= "table" then
        Config._memoryState = {}
        return Config._memoryState
    end

    Config._memoryState = decoded
    return Config._memoryState
end

function Config.saveMemoryState()
    if not Config.mod then
        return
    end

    Config._memoryState = Config._memoryState or {}
    Config.mod:SaveData(json.encode(Config._memoryState))
end

function Config.getPlayerId()
    local state = Config.loadMemoryState()
    if state.playerId and state.playerId ~= "" then
        return state.playerId
    end

    state.playerId = "player-" .. tostring(math.random(100000, 999999))
    Config.saveMemoryState()
    return state.playerId
end

function Config.getDisplayName()
    local state = Config.loadMemoryState()
    if state.displayName and state.displayName ~= "" then
        return state.displayName
    end

    state.displayName = "Runner-" .. string.sub(Config.getPlayerId(), -4)
    Config.saveMemoryState()
    return state.displayName
end

function Config.getBridgeHost()
    local state = Config.loadMemoryState()
    if state.matchmakingHost and state.matchmakingHost ~= "" then
        return state.matchmakingHost
    end
    if Config.BRIDGE_HTTP_HOST and Config.BRIDGE_HTTP_HOST ~= "" then
        return Config.BRIDGE_HTTP_HOST
    end
    return Config.MATCHMAKING_SERVER_HOST or "127.0.0.1"
end

function Config.getBridgePort()
    local state = Config.loadMemoryState()
    if state.matchmakingPort then
        return tonumber(state.matchmakingPort) or Config.BRIDGE_HTTP_PORT or 8766
    end
    return Config.BRIDGE_HTTP_PORT or Config.MATCHMAKING_SERVER_PORT or 8766
end

function Config.isLocalDevServer()
    local host = string.lower(tostring(Config.getBridgeHost() or ""))
    return host == "127.0.0.1" or host == "localhost"
end

function Config.hasRepentogon()
    return Isaac.StartNewGame ~= nil
        and MenuManager ~= nil
        and CharacterMenu ~= nil
end

_G._IsaacRanked_Config = Config
return Config
