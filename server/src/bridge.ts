import { createServer } from "node:http";
import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import WebSocket from "ws";
import type { BridgeRequest } from "../../shared/protocol.js";
import { processBridgeRequest } from "./bridge-handler.js";
import { resolveBridgeDir } from "./bridge-inbox.js";

const WS_PORT = Number(process.env.ISAAC_RANKED_WS_PORT ?? 8765);
const HTTP_PORT = Number(process.env.ISAAC_RANKED_HTTP_PORT ?? 8766);

const BRIDGE_DIR = resolveBridgeDir();
let bridgeWebSocket: WebSocket | null = null;

function ensureBridgeDir(): void {
  if (!existsSync(BRIDGE_DIR)) {
    mkdirSync(BRIDGE_DIR, { recursive: true });
  }
}

function getBridgeWebSocket(): WebSocket | null {
  return bridgeWebSocket;
}

async function handleBridgeFile(filePath: string, ws: WebSocket): Promise<void> {
  const raw = readFileSync(filePath, "utf8");
  const request = JSON.parse(raw) as BridgeRequest;
  const response = await processBridgeRequest(request, ws);
  const responsePath = join(BRIDGE_DIR, `response-${request.requestId}.json`);
  writeFileSync(responsePath, JSON.stringify(response, null, 2), "utf8");
  unlinkSync(filePath);
}

function startBridgePoller(ws: WebSocket): void {
  ensureBridgeDir();
  setInterval(() => {
    if (!existsSync(BRIDGE_DIR)) return;
    const files = readdirSync(BRIDGE_DIR).filter((f) => f.startsWith("request-") && f.endsWith(".json"));
    for (const file of files) {
      void handleBridgeFile(join(BRIDGE_DIR, file), ws).catch((err) => {
        console.error("[bridge] error:", err);
      });
    }
  }, 100);
}

export function startBridgeService(wsUrl: string): WebSocket {
  const ws = new WebSocket(wsUrl);
  bridgeWebSocket = ws;

  ws.on("open", () => {
    console.log(`[bridge] connected to ${wsUrl}`);
    console.log(`[bridge] watching ${BRIDGE_DIR}`);
    startBridgePoller(ws);
  });

  ws.on("error", (err) => {
    console.error("[bridge] websocket error:", err.message);
  });

  ws.on("close", () => {
    if (bridgeWebSocket === ws) {
      bridgeWebSocket = null;
    }
    console.log("[bridge] disconnected, reconnecting in 2s...");
    setTimeout(() => startBridgeService(wsUrl), 2000);
  });

  return ws;
}

export function startHttpBridgeApi(): void {
  ensureBridgeDir();

  const server = createServer((req, res) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");

    if (req.method === "OPTIONS") {
      res.writeHead(204);
      res.end();
      return;
    }

    if (req.url === "/health") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ ok: true, bridgeDir: BRIDGE_DIR }));
      return;
    }

    if (req.url === "/bridge-dir") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ bridgeDir: BRIDGE_DIR }));
      return;
    }

    if (req.url === "/bridge" && req.method === "POST") {
      const ws = getBridgeWebSocket();
      if (!ws || ws.readyState !== WebSocket.OPEN) {
        res.writeHead(503, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Matchmaking server bridge is not connected" }));
        return;
      }

      const chunks: Buffer[] = [];
      req.on("data", (chunk) => {
        chunks.push(chunk);
      });
      req.on("end", () => {
        void (async () => {
          try {
            const raw = Buffer.concat(chunks).toString("utf8");
            const request = JSON.parse(raw) as BridgeRequest;
            const response = await processBridgeRequest(request, ws);
            res.writeHead(200, { "Content-Type": "application/json" });
            res.end(JSON.stringify(response));
          } catch (err) {
            res.writeHead(500, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }));
          }
        })();
      });
      return;
    }

    res.writeHead(404);
    res.end();
  });

  server.listen(HTTP_PORT, () => {
    console.log(`[http] bridge API listening on port ${HTTP_PORT} (POST /bridge, GET /health)`);
  });
}

export { BRIDGE_DIR, WS_PORT, HTTP_PORT, getBridgeWebSocket };
