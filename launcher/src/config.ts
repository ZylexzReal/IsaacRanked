import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
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

/** Directory containing config.default.json (install / dev root). */
export function resolveLauncherRoot(): string {
  if (process.env.ISAAC_RANKED_LAUNCHER_ROOT) {
    return process.env.ISAAC_RANKED_LAUNCHER_ROOT;
  }

  const moduleDir = dirname(fileURLToPath(import.meta.url));
  const candidates = [
    join(moduleDir, ".."),
    join(moduleDir, "../.."),
    join(moduleDir, "../../.."),
  ];

  for (const candidate of candidates) {
    if (existsSync(join(candidate, "config.default.json"))) {
      return candidate;
    }
  }

  return join(moduleDir, "..");
}

/** Writable directory for config.json (user data when packaged). */
export function resolveConfigDirectory(): string {
  if (process.env.ISAAC_RANKED_CONFIG_DIR) {
    return process.env.ISAAC_RANKED_CONFIG_DIR;
  }
  return resolveLauncherRoot();
}

function ensureUserConfig(configDir: string, launcherRoot: string): void {
  const userPath = join(configDir, "config.json");
  if (existsSync(userPath)) {
    return;
  }

  const defaultPath = join(launcherRoot, "config.default.json");
  if (!existsSync(defaultPath)) {
    return;
  }

  mkdirSync(configDir, { recursive: true });
  writeFileSync(userPath, readFileSync(defaultPath, "utf8"), "utf8");
}

export function loadLauncherConfig(): LauncherConfig {
  const launcherRoot = resolveLauncherRoot();
  const configDir = resolveConfigDirectory();
  ensureUserConfig(configDir, launcherRoot);

  const defaultConfig = loadJsonConfig(join(launcherRoot, "config.default.json")) ?? {};
  const userConfig = loadJsonConfig(join(configDir, "config.json")) ?? {};

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
