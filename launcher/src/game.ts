import { spawn } from "node:child_process";
import { dirname } from "node:path";
import type { LauncherPaths } from "./paths.js";
import {
  snapshotRepentogonIsaacPids,
  waitForNewRepentogonIsaac,
  waitForProcessExit,
} from "./process-wait.js";
import { ensureRepentogonStealthMode, resolveRepentogonIniPath } from "./repentogon-ini.js";

const ISAAC_START_TIMEOUT_MS = 180_000;

export async function launchGame(paths: LauncherPaths): Promise<number> {
  const iniPath = resolveRepentogonIniPath();
  const stealthEnabled = ensureRepentogonStealthMode(iniPath);
  if (stealthEnabled) {
    console.log("Enabled Repentogon Stealth Mode (auto-launch Isaac).");
  }

  const knownPids = await snapshotRepentogonIsaacPids(paths.gameRoot);
  const isaacArg = `--isaac=${paths.isaacExecutable}`;

  const child = spawn(paths.repentogonLauncher, [isaacArg], {
    cwd: dirname(paths.repentogonLauncher),
    stdio: "ignore",
    windowsHide: true,
    detached: false,
  });

  await new Promise<void>((resolve, reject) => {
    child.on("error", reject);
    child.on("spawn", () => resolve());
  });

  const isaacPid = await waitForNewRepentogonIsaac(
    paths.gameRoot,
    knownPids,
    ISAAC_START_TIMEOUT_MS,
  );

  await waitForProcessExit(isaacPid);

  if (!child.killed && child.exitCode === null) {
    child.kill();
  }

  await new Promise<void>((resolve) => {
    if (child.exitCode !== null) {
      resolve();
      return;
    }
    child.on("close", () => resolve());
  });

  return 0;
}
