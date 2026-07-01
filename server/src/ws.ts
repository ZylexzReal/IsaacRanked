import type { IncomingMessage } from "node:http";
import { WebSocketServer, WebSocket } from "ws";
import type { ClientMessage, ServerMessage } from "../../shared/protocol.js";
import { PROTOCOL_VERSION } from "../../shared/protocol.js";
import { db } from "./db.js";
import { matchmaking } from "./matchmaking.js";
import { validateIntegrityReport, validateMatchStartedIntegrity } from "./anticheat.js";

export interface ClientConnection {
  ws: WebSocket;
  playerId: string | null;
  send: (msg: ServerMessage) => void;
}

function parseMessage(data: Buffer | ArrayBuffer | Buffer[]): ClientMessage | null {
  try {
    return JSON.parse(data.toString()) as ClientMessage;
  } catch {
    return null;
  }
}

export function createWebSocketServer(port: number): WebSocketServer {
  const wss = new WebSocketServer({ port });

  wss.on("error", (err: NodeJS.ErrnoException) => {
    if (err.code === "EADDRINUSE") {
      console.error(`[server] Port ${port} is already in use.`);
      console.error("[server] Another Isaac Ranked server is probably still running.");
      console.error("[server] Stop it with: npm run stop");
      console.error(`[server] Or run on another port: set ISAAC_RANKED_WS_PORT=8775 && npm run dev`);
      process.exit(1);
    }

    console.error("[server] WebSocket error:", err.message);
    process.exit(1);
  });

  wss.on("connection", (ws: WebSocket, _req: IncomingMessage) => {
    const conn: ClientConnection = {
      ws,
      playerId: null,
      send(msg) {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify(msg));
        }
      },
    };

    ws.on("message", (data) => {
      const msg = parseMessage(data as Buffer);
      if (!msg) {
        conn.send({ type: "error", code: "invalid_json", message: "Could not parse message" });
        return;
      }
      handleMessage(conn, msg);
    });

    ws.on("close", () => {
      if (conn.playerId) {
        const matchId = matchmaking.getActiveMatchId(conn.playerId);
        if (matchId) {
          matchmaking.forfeit(conn.playerId, matchId, "disconnect");
        }
        matchmaking.unregisterConnection(conn.playerId);
      }
    });
  });

  return wss;
}

function resolvePlayerId(conn: ClientConnection, msg: { playerId?: string }): string | null {
  return msg.playerId ?? conn.playerId;
}

function handleMessage(conn: ClientConnection, msg: ClientMessage): void {
  switch (msg.type) {
    case "hello": {
      if (msg.protocolVersion !== PROTOCOL_VERSION) {
        conn.send({
          type: "error",
          code: "protocol_mismatch",
          message: `Expected protocol ${PROTOCOL_VERSION}`,
        });
        return;
      }

      const player = db.getOrCreatePlayer(msg.playerId, msg.displayName);
      conn.playerId = msg.playerId;

      matchmaking.registerConnection({
        playerId: msg.playerId,
        displayName: msg.displayName,
        rating: player.rating,
        joinedAt: Date.now(),
        send: (m) => conn.send(m as ServerMessage),
      });

      conn.send({
        type: "hello_ack",
        player: {
          playerId: player.playerId,
          displayName: player.displayName,
          rating: player.rating,
          placementMatchesRemaining: player.placementMatchesRemaining,
        },
      });
      break;
    }

    case "queue_join": {
      const playerId = resolvePlayerId(conn, msg);
      if (!playerId) {
        conn.send({ type: "error", code: "not_authenticated", message: "Send hello first" });
        return;
      }

      const player = db.getPlayer(playerId);
      if (!player) {
        conn.send({ type: "error", code: "not_authenticated", message: "Unknown player" });
        return;
      }

      const status = matchmaking.joinQueue({
        playerId,
        displayName: player.displayName,
        rating: player.rating,
        joinedAt: Date.now(),
        unlockedCharacters: msg.unlockedCharacters,
        send: (m) => conn.send(m as ServerMessage),
      });

      conn.send({
        type: "queue_update",
        position: status.position,
        estimatedWaitSec: status.estimatedWaitSec,
        rating: player.rating,
      });
      break;
    }

    case "queue_leave": {
      const playerId = resolvePlayerId(conn, msg);
      if (playerId) {
        matchmaking.leaveQueue(playerId);
        conn.send({
          type: "queue_update",
          position: 0,
          estimatedWaitSec: 0,
          rating: db.getPlayer(playerId)?.rating ?? 1000,
        });
      }
      break;
    }

    case "match_started": {
      const startedCheck = validateMatchStartedIntegrity(msg.integrity);
      if (!startedCheck.ok) {
        matchmaking.reportIntegrityViolation(
          msg.playerId,
          msg.matchId,
          startedCheck.reason ?? "integrity_preflight_failed"
        );
        break;
      }

      matchmaking.markMatchStarted(msg.matchId, msg.playerId, msg.actualSeed, msg.actualPlayerType);
      break;
    }

    case "progress_event": {
      matchmaking.reportProgress(msg.playerId, msg.event);
      break;
    }

    case "match_result": {
      const { payload } = msg;
      matchmaking.reportResult(
        msg.playerId,
        payload.matchId,
        payload.result,
        payload.elapsedMs,
        payload.floor,
        payload.reason,
        payload.result !== "invalid"
      );
      break;
    }

    case "forfeit": {
      matchmaking.forfeit(msg.playerId, msg.matchId, msg.reason);
      break;
    }

    case "heartbeat": {
      const playerId = resolvePlayerId(conn, msg);
      if (playerId) {
        matchmaking.heartbeat(playerId);
      }
      break;
    }

    case "integrity_violation": {
      const violationCheck = validateIntegrityReport(msg.report, { strictPreflight: false });
      const reason = violationCheck.ok
        ? msg.report.violationReason ?? "integrity_violation"
        : violationCheck.reason ?? msg.report.violationReason ?? "integrity_violation";
      matchmaking.reportIntegrityViolation(msg.playerId, msg.report.matchId, reason);
      break;
    }

    default:
      conn.send({ type: "error", code: "unknown_type", message: "Unknown message type" });
  }
}
