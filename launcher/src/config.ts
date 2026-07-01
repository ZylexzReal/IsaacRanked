import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { LauncherConfig } from "./paths.js";

const DEFAULT_CONFIG: LauncherConfig = {
  matchmakingHost: "127.0.0.1",
  matchmakingPort: 8766,
};

function loadJsonConfig(path: string): Partial<LauncherConfig> | null {
  if (!existsSync(path)) {
    return null;
  }

  try {
    const parsed = JSON.parse(readFileSync(path, "utf8")) as Partial<LauncherConfig>;
    return parsed;
  } catch {
    return null;
  }
}

export function loadLauncherConfig(): LauncherConfig {
  const launcherRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
  const defaultConfig = loadJsonConfig(join(launcherRoot, "config.default.json")) ?? {};
  const userConfig = loadJsonConfig(join(launcherRoot, "config.json")) ?? {};

  let merged: LauncherConfig = {
    ...DEFAULT_CONFIG,
    ...defaultConfig,
    ...userConfig,
  };

  if (process.env.ISAAC_RANKED_MATCHMAKING_HOST) {
    merged.matchmakingHost = process.env.ISAAC_RANKED_MATCHMAKING_HOST;
  }
  if (process.env.ISAAC_RANKED_HTTP_PORT) {
    merged.matchmakingPort = Number(process.env.ISAAC_RANKED_HTTP_PORT) || merged.matchmakingPort;
  }

  return merged;
}
