if _G._IsaacRanked_Json then return _G._IsaacRanked_Json end

local Json = {}

local escape_map = {
    ["\\"] = "\\\\",
    ["\""] = "\\\"",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
}

local function escapeString(str)
    return '"' .. tostring(str):gsub('[\\"\n\r\t]', escape_map) .. '"'
end

function Json.encode(value)
    local t = type(value)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "number" then
        return tostring(value)
    elseif t == "string" then
        return escapeString(value)
    elseif t == "table" then
        local isArray = #value > 0
        if isArray then
            local parts = {}
            for i = 1, #value do
                parts[#parts + 1] = Json.encode(value[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        end

        local parts = {}
        for k, v in pairs(value) do
            parts[#parts + 1] = escapeString(tostring(k)) .. ":" .. Json.encode(v)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

local function skipWhitespace(str, i)
    while i <= #str do
        local c = str:sub(i, i)
        if c ~= " " and c ~= "\n" and c ~= "\r" and c ~= "\t" then
            break
        end
        i = i + 1
    end
    return i
end

local function parseValue(str, i)
    i = skipWhitespace(str, i)
    local c = str:sub(i, i)

    if c == "{" then
        local obj = {}
        i = i + 1
        i = skipWhitespace(str, i)
        if str:sub(i, i) == "}" then
            return obj, i + 1
        end
        while i <= #str do
            i = skipWhitespace(str, i)
            local key
            if str:sub(i, i) == '"' then
                local close = str:find('"', i + 1)
                key = str:sub(i + 1, close - 1)
                i = close + 1
            else
                local close = str:find('[,:}]', i)
                key = str:sub(i, close - 1)
                i = close
            end
            i = skipWhitespace(str, i)
            if str:sub(i, i) ~= ":" then
                error("expected colon")
            end
            i = i + 1
            local val
            val, i = parseValue(str, i)
            obj[key] = val
            i = skipWhitespace(str, i)
            if str:sub(i, i) == "}" then
                return obj, i + 1
            end
            if str:sub(i, i) ~= "," then
                error("expected comma")
            end
            i = i + 1
        end
    elseif c == "[" then
        local arr = {}
        i = i + 1
        i = skipWhitespace(str, i)
        if str:sub(i, i) == "]" then
            return arr, i + 1
        end
        while i <= #str do
            local val
            val, i = parseValue(str, i)
            arr[#arr + 1] = val
            i = skipWhitespace(str, i)
            if str:sub(i, i) == "]" then
                return arr, i + 1
            end
            if str:sub(i, i) ~= "," then
                error("expected comma")
            end
            i = i + 1
        end
    elseif c == '"' then
        local close = str:find('"', i + 1)
        return str:sub(i + 1, close - 1), close + 1
    elseif str:sub(i, i + 3) == "true" then
        return true, i + 4
    elseif str:sub(i, i + 4) == "false" then
        return false, i + 5
    elseif str:sub(i, i + 3) == "null" then
        return nil, i + 4
    else
        local close = str:find('[,%]}]', i)
        local token = str:sub(i, close - 1)
        if token:find("%.") then
            return tonumber(token), close
        end
        return tonumber(token), close
    end
end

function Json.decode(str)
    local value, _ = parseValue(str, 1)
    return value
end

_G._IsaacRanked_Json = Json
return Json
