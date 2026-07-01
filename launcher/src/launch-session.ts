import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
  probeRemoteBridge,
  startRemoteBridgeAgent,
} from "../../server/src/bridge-agent.js";
import { loadLauncherConfig } from "./config.js";
import { launchGame } from "./game.js";
import { buildRemoteBridgeUrl, resolveLauncherPaths, type LauncherPaths } from "./paths.js";

export type LaunchPhase = "idle" | "checking" | "bridge" | "launching" | "playing" | "done" | "error";

export interface LaunchStatusEvent {
  phase: LaunchPhase;
  message: string;
  level?: "info" | "warn" | "error";
  paths?: LauncherPaths;
  serverOnline?: boolean;
}

export interface LaunchSessionOptions {
  onStatus?: (event: LaunchStatusEvent) => void;
}

function writeLauncherMarker(modDir: string): void {
  const markerPath = join(modDir, "scripts", "launcher_active.lua");
  const content = "return { active = true, updatedAt = os.time and os.time() or 0 }\n";
  writeFileSync(markerPath, content, "utf8");
}

function emit(options: LaunchSessionOptions | undefined, event: LaunchStatusEvent): void {
  options?.onStatus?.(event);
}

export async function runLaunchSession(options?: LaunchSessionOptions): Promise<number> {
  emit(options, { phase: "checking", message: "Loading configuration..." });

  const config = loadLauncherConfig();
  const paths = resolveLauncherPaths(config);
  const remoteUrl = buildRemoteBridgeUrl(config);

  process.env.ISAAC_RANKED_MOD_DIR = paths.modDir;
  process.env.ISAAC_RANKED_LOG_PATH = paths.logPath;
  process.env.ISAAC_RANKED_BRIDGE_DIR = paths.bridgeDir;
  process.env.ISAAC_RANKED_REMOTE_BRIDGE_URL = remoteUrl;
  process.env.ISAAC_RANKED_BRIDGE_HTTP_HOST = config.matchmakingHost;
  process.env.ISAAC_RANKED_HTTP_PORT = String(config.matchmakingPort);

  mkdirSync(paths.bridgeDir, { recursive: true });
  writeLauncherMarker(paths.modDir);

  emit(options, {
    phase: "checking",
    message: `Server: ${remoteUrl}`,
    paths,
  });

  let serverOnline = false;
  try {
    await probeRemoteBridge(remoteUrl);
    serverOnline = true;
    emit(options, {
      phase: "checking",
      message: "Matchmaking server is online.",
      serverOnline: true,
      paths,
    });
  } catch (err) {
    emit(options, {
      phase: "checking",
      message: "Matchmaking server is offline. Bridge will retry when you queue.",
      level: "warn",
      serverOnline: false,
      paths,
    });
    emit(options, {
      phase: "checking",
      message: String(err),
      level: "warn",
      serverOnline: false,
      paths,
    });
  }

  emit(options, { phase: "bridge", message: "Starting ranked bridge...", serverOnline, paths });
  startRemoteBridgeAgent({
    remoteUrl,
    modDir: paths.modDir,
    logPath: paths.logPath,
  });

  emit(options, { phase: "launching", message: "Launching Isaac...", serverOnline, paths });
  const exitCode = await launchGame(paths);

  emit(options, {
    phase: "done",
    message: `Isaac closed (exit code ${exitCode}).`,
    serverOnline,
    paths,
  });

  return exitCode;
}
