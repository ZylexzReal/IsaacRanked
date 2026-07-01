import { createReadStream, existsSync, readFileSync, statSync, writeFileSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";
import { createInterface } from "node:readline";
import type { BridgeRequest, BridgeResponse } from "../../shared/protocol.js";

export const BRIDGE_SEND_PREFIX = "[IsaacRanked][BRIDGE_SEND] ";

export function resolveBridgeDir(): string {
  if (process.env.ISAAC_RANKED_BRIDGE_DIR) {
    return process.env.ISAAC_RANKED_BRIDGE_DIR;
  }

  const bridgeConfigPath = join(dirname(fileURLToPath(import.meta.url)), "..", ".bridge-dir");
  if (existsSync(bridgeConfigPath)) {
    const configured = readFileSync(bridgeConfigPath, "utf8").trim();
    if (configured) {
      return configured;
    }
  }

  return join(homedir(), "Documents", "My Games", "Binding of Isaac Repentance+", "isaac-ranked-bridge");
}

export function resolveLogPath(): string {
  if (process.env.ISAAC_RANKED_LOG_PATH) {
    return process.env.ISAAC_RANKED_LOG_PATH;
  }

  return join(homedir(), "Documents", "My Games", "Binding of Isaac Repentance+", "log.txt");
}

export function resolveModDir(): string | null {
  if (process.env.ISAAC_RANKED_MOD_DIR) {
    return process.env.ISAAC_RANKED_MOD_DIR;
  }

  const modConfigPath = join(dirname(fileURLToPath(import.meta.url)), "..", ".mod-dir");
  if (existsSync(modConfigPath)) {
    const configured = readFileSync(modConfigPath, "utf8").trim();
    if (configured) {
      return configured;
    }
  }

  return null;
}

export function writeInboxLua(modDir: string, payload: { version: number; responses: BridgeResponse[] }): void {
  const encoded = JSON.stringify(payload);
  const luaContent = `_G._IsaacRanked_InboxEnvelope = [==[${encoded}]==]\nreturn _G._IsaacRanked_InboxEnvelope\n`;
  const bridgeDir = resolveBridgeDir();

  const targets = [
    join(modDir, "scripts", "bridge_inbox.lua"),
    join(modDir, "bridge", "inbox.lua"),
    join(bridgeDir, "inbox.lua"),
  ];

  for (const target of targets) {
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, luaContent, "utf8");
  }
}

export function startLogBridgeForwarder(options: {
  modDir: string;
  logPath: string;
  label: string;
  canProcess: () => boolean;
  forward: (request: BridgeRequest) => Promise<BridgeResponse>;
}): void {
  const { modDir, logPath, label, canProcess, forward } = options;

  let offset = 0;
  let inboxVersion = 0;
  const pendingResponses: BridgeResponse[] = [];
  let processing = false;
  const requestQueue: BridgeRequest[] = [];

  const flushInbox = () => {
    inboxVersion += 1;
    writeInboxLua(modDir, { version: inboxVersion, responses: [...pendingResponses] });
    pendingResponses.length = 0;
  };

  const processQueue = async () => {
    if (processing || !canProcess() || requestQueue.length === 0) {
      return;
    }

    processing = true;
    try {
      while (requestQueue.length > 0) {
        const request = requestQueue.shift();
        if (!request) {
          continue;
        }

        const response = await forward(request);
        pendingResponses.push(response);
      }
      if (pendingResponses.length > 0) {
        flushInbox();
      }
    } catch (err) {
      console.error(`[${label}] error:`, err);
    } finally {
      processing = false;
      if (requestQueue.length > 0) {
        void processQueue();
      }
    }
  };

  const handleLine = (line: string) => {
    const index = line.indexOf(BRIDGE_SEND_PREFIX);
    if (index < 0) {
      return;
    }

    const raw = line.slice(index + BRIDGE_SEND_PREFIX.length).trim();
    if (!raw) {
      return;
    }

    try {
      const request = JSON.parse(raw) as BridgeRequest;
      requestQueue.push(request);
      void processQueue();
    } catch (err) {
      console.error(`[${label}] failed to parse bridge send:`, err);
    }
  };

  const tailFrom = (start: number) => {
    if (!existsSync(logPath)) {
      return;
    }

    const stream = createReadStream(logPath, { start, encoding: "utf8" });
    const rl = createInterface({ input: stream, crlfDelay: Infinity });
    rl.on("line", handleLine);
    rl.on("close", () => {
      try {
        offset = statSync(logPath).size;
      } catch {
        offset = 0;
      }
    });
  };

  const poll = () => {
    if (!existsSync(logPath)) {
      return;
    }

    try {
      const size = statSync(logPath).size;
      if (size < offset) {
        offset = 0;
      }
      if (size > offset) {
        tailFrom(offset);
      }
    } catch (err) {
      console.error(`[${label}] poll error:`, err);
    }
  };

  if (existsSync(logPath)) {
    offset = statSync(logPath).size;
  }

  console.log(`[${label}] watching ${logPath}`);
  console.log(
    `[${label}] writing inbox to ${join(modDir, "scripts", "bridge_inbox.lua")}, `
      + `${join(modDir, "bridge", "inbox.lua")}, and ${join(resolveBridgeDir(), "inbox.lua")}`,
  );
  setInterval(poll, 100);
  setInterval(() => {
    void processQueue();
  }, 250);
}
