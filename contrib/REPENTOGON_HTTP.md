# Repentogon HTTP API (required for Steam Workshop remote matchmaking)

Isaac Ranked connects to a remote matchmaking server over HTTP. Repentogon mods cannot use `socket.core` or `io` in the standard sandbox, so ranked play needs a small HTTP helper exposed by Repentogon (libcurl is already used internally by the launcher).

## Proposed Lua API

```lua
-- Synchronous POST (preferred for ranked bridge calls)
Http.PostSync(url, body, contentType) -> statusCode, responseBody

-- Example
local status, body = Http.PostSync(
    "http://203.0.113.10:8766/bridge",
    '{"requestId":"req-1","message":{"type":"hello"}}',
    "application/json"
)
```

Isaac Ranked already checks for `Http.PostSync` in `scripts/http_bridge.lua`.

## Why this is needed

| Transport | Works on Steam without extra tools? |
|-----------|-------------------------------------|
| Log bridge (`DebugString` → local Node process) | No — needs a local process |
| File bridge (`Directory` / `io`) | No — blocked or local-only |
| LuaSocket (`require("socket")`) | No — `socket.core` missing |
| **Repentogon `Http.PostSync`** | **Yes** |

## Until this ships in Repentogon

- **Players (Steam):** need Repentogon with `Http.PostSync`, or matchmaking will not connect.
- **Developers:** set `Config.BRIDGE_HTTP_HOST = "127.0.0.1"` in `config.lua` and run `npm run dev` locally (log bridge fallback).

## Implementation notes for Repentogon maintainers

- Reuse existing libcurl / `DownloadAsString` infrastructure.
- Timeout: 10 seconds.
- Only allow `http://` initially (TLS can be added later).
- Optional allowlist: `ISAAC_RANKED_HTTP_ALLOW_HOST` env for testing.
