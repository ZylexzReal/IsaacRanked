import { execFile } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { promisify } from "node:util";
import { resolveLauncherRoot } from "./config.js";

const execFileAsync = promisify(execFile);

const GITHUB_OWNER = "ZylexzReal";
const GITHUB_REPO = "IsaacRanked";
const REMOTE_PACKAGE_URL =
  `https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/main/launcher/package.json`;

export interface UpdateStatusEvent {
  phase: "checking" | "downloading" | "installing" | "ready" | "error" | "idle";
  message: string;
  level?: "info" | "warn" | "error";
  localVersion?: string;
  remoteVersion?: string;
}

function parseVersion(version: string): [number, number, number] {
  const parts = version.trim().split(".").map((part) => Number.parseInt(part, 10));
  return [parts[0] || 0, parts[1] || 0, parts[2] || 0];
}

export function isRemoteVersionNewer(localVersion: string, remoteVersion: string): boolean {
  const local = parseVersion(localVersion);
  const remote = parseVersion(remoteVersion);
  for (let i = 0; i < 3; i += 1) {
    if (remote[i] > local[i]) {
      return true;
    }
    if (remote[i] < local[i]) {
      return false;
    }
  }
  return false;
}

export function readLocalLauncherVersion(): string {
  const launcherRoot = resolveLauncherRoot();
  const packagePath = join(launcherRoot, "package.json");
  const pkg = JSON.parse(readFileSync(packagePath, "utf8")) as { version?: string };
  return pkg.version ?? "0.0.0";
}

export async function fetchRemoteLauncherVersion(): Promise<string | null> {
  try {
    const response = await fetch(REMOTE_PACKAGE_URL, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(12_000),
    });
    if (!response.ok) {
      return null;
    }
    const pkg = await response.json() as { version?: string };
    return pkg.version ?? null;
  } catch {
    return null;
  }
}

function findRepoRoot(startDir: string): string | null {
  let dir = startDir;
  while (true) {
    if (existsSync(join(dir, ".git"))) {
      return dir;
    }
    const parent = dirname(dir);
    if (parent === dir) {
      return null;
    }
    dir = parent;
  }
}

async function updateDevCheckout(
  onStatus: (event: UpdateStatusEvent) => void,
): Promise<boolean> {
  const launcherRoot = resolveLauncherRoot();
  const repoRoot = findRepoRoot(launcherRoot);
  if (!repoRoot) {
    onStatus({
      phase: "idle",
      message: "Dev update skipped (not a git checkout).",
      level: "warn",
    });
    return false;
  }

  onStatus({ phase: "downloading", message: "Pulling latest launcher from GitHub..." });
  await execFileAsync("git", ["pull", "--ff-only", "origin", "main"], {
    cwd: repoRoot,
    windowsHide: true,
  });

  onStatus({ phase: "installing", message: "Installing launcher dependencies..." });
  await execFileAsync("npm", ["install"], {
    cwd: join(repoRoot, "launcher"),
    windowsHide: true,
  });

  onStatus({ phase: "installing", message: "Building launcher..." });
  await execFileAsync("npm", ["run", "build"], {
    cwd: join(repoRoot, "launcher"),
    windowsHide: true,
  });

  onStatus({ phase: "ready", message: "Launcher updated. Restarting..." });
  return true;
}

async function updatePackagedApp(
  onStatus: (event: UpdateStatusEvent) => void,
): Promise<boolean> {
  const { autoUpdater } = await import("electron-updater");
  autoUpdater.autoDownload = true;
  autoUpdater.autoInstallOnAppQuit = false;

  return await new Promise<boolean>((resolve) => {
    let settled = false;

    const finish = (updated: boolean) => {
      if (settled) {
        return;
      }
      settled = true;
      resolve(updated);
    };

    autoUpdater.on("update-available", () => {
      onStatus({ phase: "downloading", message: "Downloading launcher update..." });
    });

    autoUpdater.on("update-not-available", () => {
      onStatus({
        phase: "idle",
        message: "Launcher is up to date (no release installer yet).",
      });
      finish(false);
    });

    autoUpdater.on("update-downloaded", () => {
      onStatus({ phase: "installing", message: "Installing launcher update..." });
      autoUpdater.quitAndInstall(false, true);
      finish(true);
    });

    autoUpdater.on("error", (err) => {
      onStatus({
        phase: "error",
        message: `Auto-update failed: ${err.message}`,
        level: "warn",
      });
      finish(false);
    });

    void autoUpdater.checkForUpdates().catch((err: Error) => {
      onStatus({
        phase: "error",
        message: `Update check failed: ${err.message}`,
        level: "warn",
      });
      finish(false);
    });
  });
}

export async function checkAndApplyLauncherUpdates(options: {
  isPackaged: boolean;
  onStatus: (event: UpdateStatusEvent) => void;
}): Promise<boolean> {
  const { isPackaged, onStatus } = options;
  const localVersion = readLocalLauncherVersion();

  onStatus({
    phase: "checking",
    message: "Checking for launcher updates on GitHub...",
    localVersion,
  });

  const remoteVersion = await fetchRemoteLauncherVersion();
  if (!remoteVersion) {
    onStatus({
      phase: "error",
      message: "Could not reach GitHub to check for updates.",
      level: "warn",
      localVersion,
    });
    return false;
  }

  if (!isRemoteVersionNewer(localVersion, remoteVersion)) {
    onStatus({
      phase: "idle",
      message: `Launcher is up to date (v${localVersion}).`,
      localVersion,
      remoteVersion,
    });
    return false;
  }

  onStatus({
    phase: "downloading",
    message: `Update available: v${localVersion} → v${remoteVersion}`,
    localVersion,
    remoteVersion,
  });

  if (isPackaged) {
    return updatePackagedApp(onStatus);
  }

  try {
    const updated = await updateDevCheckout(onStatus);
    return updated;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    onStatus({
      phase: "error",
      message: `Dev update failed: ${message}`,
      level: "error",
      localVersion,
      remoteVersion,
    });
    return false;
  }
}
