import { pathToFileURL } from "node:url";
import type { BridgeRequest, BridgeResponse } from "../../shared/protocol.js";
import {
  resolveLogPath,
  resolveModDir,
  startLogBridgeForwarder,
} from "./bridge-inbox.js";

export interface RemoteBridgeOptions {
  remoteUrl: string;
  modDir: string;
  logPath: string;
}

export function resolveRemoteBridgeUrl(): string {
  const configured = process.env.ISAAC_RANKED_REMOTE_BRIDGE_URL?.trim();
  if (configured) {
    return configured.replace(/\/+$/, "");
  }

  const host = process.env.ISAAC_RANKED_BRIDGE_HTTP_HOST?.trim();
  const port = process.env.ISAAC_RANKED_HTTP_PORT ?? "8766";
  if (host) {
    return `http://${host}:${port}/bridge`;
  }

  return "";
}

const BRIDGE_FETCH_TIMEOUT_MS = 15_000;

async function forwardToRemoteBridge(request: BridgeRequest, remoteUrl: string): Promise<BridgeResponse> {
  const response = await fetch(remoteUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(request),
    signal: AbortSignal.timeout(BRIDGE_FETCH_TIMEOUT_MS),
  });

  const body = await response.text();
  if (!response.ok) {
    throw new Error(`Remote bridge HTTP ${response.status}: ${body}`);
  }

  return JSON.parse(body) as BridgeResponse;
}

export async function probeRemoteBridge(remoteUrl: string): Promise<void> {
  const healthUrl = remoteUrl.replace(/\/bridge$/, "/health");
  const response = await fetch(healthUrl);
  if (!response.ok) {
    throw new Error(`Health check failed: HTTP ${response.status}`);
  }
}

export function startRemoteBridgeAgent(options: RemoteBridgeOptions): void {
  const { remoteUrl, modDir, logPath } = options;

  void (async () => {
    try {
      await probeRemoteBridge(remoteUrl);
      console.log(`[bridge-agent] connected to ${remoteUrl}`);
    } catch (err) {
      console.error("[bridge-agent] could not reach remote server:", err);
      console.error("[bridge-agent] continuing anyway; requests will retry when the server is reachable.");
    }

    startLogBridgeForwarder({
      modDir,
      logPath,
      label: "isaac-ranked-launcher",
      canProcess: () => true,
      forward: (request) => forwardToRemoteBridge(request, remoteUrl),
    });
  })();
}

function main(): void {
  const remoteUrl = resolveRemoteBridgeUrl();
  if (!remoteUrl) {
    console.error(
      "Set ISAAC_RANKED_REMOTE_BRIDGE_URL (e.g. http://YOUR_VPS_IP:8766/bridge) "
        + "or ISAAC_RANKED_BRIDGE_HTTP_HOST + ISAAC_RANKED_HTTP_PORT.",
    );
    process.exit(1);
  }

  const modDir = resolveModDir();
  if (!modDir) {
    console.error(
      "Mod directory not configured. Run scripts/install-mod.ps1 or set ISAAC_RANKED_MOD_DIR.",
    );
    process.exit(1);
  }

  startRemoteBridgeAgent({
    remoteUrl,
    modDir,
    logPath: resolveLogPath(),
  });
}

const isDirectRun = process.argv[1]
  && import.meta.url === pathToFileURL(process.argv[1]).href;

if (isDirectRun) {
  main();
}
