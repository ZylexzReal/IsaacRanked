import WebSocket from "ws";
import type { BridgeRequest, BridgeResponse } from "../../shared/protocol.js";
import { processBridgeRequest } from "./bridge-handler.js";
import { getBridgeWebSocket } from "./bridge.js";
import {
  resolveLogPath,
  resolveModDir,
  startLogBridgeForwarder,
} from "./bridge-inbox.js";

export function startLogBridgeWatcher(): void {
  const logPath = resolveLogPath();
  const modDir = resolveModDir();
  if (!modDir) {
    console.warn("[bridge-log] mod directory not configured; log bridge disabled");
    return;
  }

  startLogBridgeForwarder({
    modDir,
    logPath,
    label: "bridge-log",
    canProcess: () => {
      const ws = getBridgeWebSocket();
      return ws !== null && ws.readyState === WebSocket.OPEN;
    },
    forward: (request: BridgeRequest) => {
      const ws = getBridgeWebSocket();
      if (!ws || ws.readyState !== WebSocket.OPEN) {
        return Promise.reject(new Error("Local matchmaking bridge is not connected"));
      }
      return processBridgeRequest(request, ws);
    },
  });
}
