import WebSocket from "ws";
import type { BridgeRequest, BridgeResponse, ClientMessage, ServerMessage } from "../../shared/protocol.js";

const TERMINAL_TYPES = new Set([
  "hello_ack",
  "queue_update",
  "match_found",
  "match_resolved",
  "error",
]);

function isTerminal(msg: ServerMessage, request: ClientMessage): boolean {
  if (msg.type === "match_found") return true;
  if (msg.type === "match_resolved") return true;
  if (msg.type === "error") return true;
  if (msg.type === "hello_ack") return true;
  if (msg.type === "queue_update" && request.type !== "queue_join") return true;
  return false;
}

export function processBridgeRequest(request: BridgeRequest, ws: WebSocket): Promise<BridgeResponse> {
  return new Promise((resolve) => {
    const messages: ServerMessage[] = [];
    const requestId = request.requestId;
    let settled = false;
    let idleTimer: NodeJS.Timeout | null = null;

    const finish = (error?: string) => {
      if (settled) return;
      settled = true;
      ws.off("message", onMessage);
      if (idleTimer) clearTimeout(idleTimer);
      clearTimeout(hardTimer);
      resolve({ requestId, messages, error });
    };

    const scheduleIdleFinish = () => {
      if (idleTimer) clearTimeout(idleTimer);
      idleTimer = setTimeout(() => finish(), 350);
    };

    const onMessage = (data: WebSocket.RawData) => {
      try {
        const msg = JSON.parse(data.toString()) as ServerMessage;
        messages.push(msg);

        if (isTerminal(msg, request.message)) {
          if (msg.type === "queue_update" && request.message.type === "queue_join") {
            const hasMatch = messages.some((m) => m.type === "match_found");
            if (!hasMatch) {
              scheduleIdleFinish();
              return;
            }
          }
          finish();
          return;
        }

        scheduleIdleFinish();
      } catch {
        finish("Failed to parse server response");
      }
    };

    const hardTimer = setTimeout(
      () => finish(messages.length ? undefined : "Bridge request timed out"),
      request.message.type === "queue_join" ? 8000 : 5000
    );

    ws.on("message", onMessage);

    const send = () => ws.send(JSON.stringify(request.message));
    if (ws.readyState === WebSocket.OPEN) {
      send();
    } else {
      ws.once("open", send);
    }
  });
}
