import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
  probeRemoteBridge,
  startRemoteBridgeAgent,
} from "../../server/src/bridge-agent.js";
import { loadLauncherConfig } from "./config.js";
import { launchGame } from "./game.js";
import { buildRemoteBridgeUrl, resolveLauncherPaths } from "./paths.js";

function printHeader(): void {
  console.log("");
  console.log("Isaac Ranked Launcher");
  console.log("=====================");
  console.log("");
}

function writeLauncherMarker(modDir: string): void {
  const markerPath = join(modDir, "scripts", "launcher_active.lua");
  const content = "return { active = true, updatedAt = os.time and os.time() or 0 }\n";
  writeFileSync(markerPath, content, "utf8");
}

async function main(): Promise<void> {
  printHeader();

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

  console.log(`Game:      ${paths.gameRoot}`);
  console.log(`Mod:       ${paths.modDir}`);
  console.log(`Log:       ${paths.logPath}`);
  console.log(`Repentogon: ${paths.repentogonLauncher}`);
  console.log(`Isaac:     ${paths.isaacExecutable}`);
  console.log(`Server:    ${remoteUrl}`);
  console.log("");

  try {
    await probeRemoteBridge(remoteUrl);
    console.log("Matchmaking server: online");
  } catch (err) {
    console.warn("Matchmaking server: offline (bridge will retry when you queue)");
    console.warn(String(err));
  }

  console.log("");
  console.log("Starting ranked bridge...");
  startRemoteBridgeAgent({
    remoteUrl,
    modDir: paths.modDir,
    logPath: paths.logPath,
  });

  console.log("Launching Isaac...");
  console.log("");

  const exitCode = await launchGame(paths);
  console.log("");
  console.log(`Isaac closed (exit code ${exitCode}). Ranked bridge stopped.`);
}

main().catch((err) => {
  console.error("");
  console.error("Launcher failed:");
  console.error(err instanceof Error ? err.message : String(err));
  process.exit(1);
});
