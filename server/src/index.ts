import { createWebSocketServer } from "./ws.js";
import { startBridgeService, startHttpBridgeApi, WS_PORT } from "./bridge.js";
import { startLogBridgeWatcher } from "./bridge-log.js";
import { matchmaking } from "./matchmaking.js";

console.log(`[server] Isaac Ranked matchmaking starting on ws://localhost:${WS_PORT}`);

createWebSocketServer(WS_PORT);
startHttpBridgeApi();
startBridgeService(`ws://localhost:${WS_PORT}`);
if (process.env.ISAAC_RANKED_DISABLE_LOG_BRIDGE !== "1") {
  startLogBridgeWatcher();
} else {
  console.log("[server] log bridge disabled (VPS/remote mode)");
}

setInterval(() => {
  for (const playerId of matchmaking.getStalePlayerIds()) {
    const matchId = matchmaking.getActiveMatchId(playerId);
    if (matchId) {
      matchmaking.forfeit(playerId, matchId, "heartbeat_timeout");
    }
    matchmaking.unregisterConnection(playerId);
    console.log(`[server] removed stale connection: ${playerId}`);
  }

  matchmaking.tick();
}, 2000);

console.log("[server] ready");
