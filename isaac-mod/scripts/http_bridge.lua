if _G._IsaacRanked_HttpBridge then return _G._IsaacRanked_HttpBridge end

local HttpBridge = {}

local cachedSocketModule = nil
local socketProbeDone = false
local socketProbeError = nil

local function extractHttpBody(raw)
    if not raw or raw == "" then
        return nil
    end

    local body = raw:match("\r\n\r\n(.*)$")
    if body and body ~= "" then
        return body
    end

    return raw
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
            return mod
        end
        if not ok then
            socketProbeError = tostring(mod)
        end
    end

    if package and type(package.loaded) == "table" and type(package.loaded.socket) == "table" then
        cachedSocketModule = package.loaded.socket
        return cachedSocketModule
    end

    if type(socket) == "table" and type(socket.tcp) == "function" then
        cachedSocketModule = socket
        return cachedSocketModule
    end

    cachedSocketModule = false
    return nil
end

local function postViaRepentogonHttp(url, payloadJson)
    if type(Http) ~= "table" then
        return nil, "Http API unavailable"
    end

    if type(Http.PostSync) == "function" then
        local ok, status, body = pcall(Http.PostSync, url, payloadJson, "application/json")
        if not ok then
            return nil, tostring(status)
        end
        if tonumber(status) ~= 200 then
            return nil, "HTTP " .. tostring(status)
        end
        return body, nil
    end

    return nil, "Http API unavailable"
end

local function postViaIsaacSocket(url, payloadJson)
    if type(IsaacSocket) ~= "table" or type(IsaacSocket.HttpClient) ~= "table" then
        return nil, "IsaacSocket unavailable"
    end

    local client = IsaacSocket.HttpClient
    for _, methodName in ipairs({ "PostSync", "RequestSync", "Post" }) do
        local method = client[methodName]
        if type(method) == "function" then
            local ok, status, body = pcall(method, client, url, payloadJson, "application/json")
            if ok and body and body ~= "" then
                return body, nil
            end
            if not ok then
                return nil, tostring(status)
            end
        end
    end

    return nil, "IsaacSocket HTTP unavailable"
end

local function postViaSocketTcp(host, port, payloadJson)
    local socketModule = getSocketModule()
    if not socketModule then
        return nil, "Socket library unavailable (" .. tostring(socketProbeError) .. ")"
    end

    local tcp = socketModule.tcp()
    if not tcp then
        return nil, "Could not create TCP socket"
    end

    tcp:settimeout(10)
    local okConnect, connectErr = tcp:connect(host, port)
    if not okConnect then
        tcp:close()
        return nil, "Could not reach matchmaking server at "
            .. host .. ":" .. tostring(port)
            .. " (" .. tostring(connectErr) .. ")"
    end

    local request = table.concat({
        "POST /bridge HTTP/1.1\r\n",
        "Host: ", host, "\r\n",
        "Content-Type: application/json\r\n",
        "Connection: close\r\n",
        "Content-Length: ", tostring(#payloadJson), "\r\n",
        "\r\n",
        payloadJson,
    })

    local sent, sendErr = tcp:send(request)
    if not sent then
        tcp:close()
        return nil, "Bridge HTTP send failed: " .. tostring(sendErr)
    end

    local chunks = {}
    while true do
        local chunk, recvErr, partial = tcp:receive(8192)
        if chunk and chunk ~= "" then
            table.insert(chunks, chunk)
        end
        if partial and partial ~= "" then
            table.insert(chunks, partial)
        end
        if recvErr == "closed" then
            break
        end
        if not chunk and recvErr ~= "timeout" then
            break
        end
        if not chunk and recvErr == "timeout" and #chunks > 0 then
            break
        end
    end
    tcp:close()

    local raw = table.concat(chunks)
    local body = extractHttpBody(raw)
    if not body or body == "" then
        return nil, "Empty bridge HTTP response"
    end

    return body, nil
end

function HttpBridge.getSocketProbeError()
    return socketProbeError
end

function HttpBridge.postBridge(payloadJson, host, port)
    local url = "http://" .. host .. ":" .. tostring(port) .. "/bridge"

    local body, err = postViaRepentogonHttp(url, payloadJson)
    if body then
        return body, nil, "repentogon-http"
    end

    body, err = postViaIsaacSocket(url, payloadJson)
    if body then
        return body, nil, "isaacsocket-http"
    end

    body, err = postViaSocketTcp(host, port, payloadJson)
    if body then
        return body, nil, "socket-tcp"
    end

    return nil, err or "No HTTP client available", nil
end

_G._IsaacRanked_HttpBridge = HttpBridge
return HttpBridge
