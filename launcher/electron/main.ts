import { app, BrowserWindow, ipcMain, shell } from "electron";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { runLaunchSession } from "../src/launch-session.js";
import type { LaunchStatusEvent } from "../src/launch-session.js";
import { checkAndApplyLauncherUpdates } from "../src/updater.js";
import type { UpdateStatusEvent } from "../src/updater.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

let mainWindow: BrowserWindow | null = null;
let sessionRunning = false;
let quittingAfterSession = false;

function configurePackagedPaths(): void {
  if (!app.isPackaged) {
    return;
  }

  process.env.ISAAC_RANKED_LAUNCHER_ROOT = process.resourcesPath;
  process.env.ISAAC_RANKED_CONFIG_DIR = app.getPath("userData");
}

function resolveUiPath(): string {
  return join(__dirname, "index.html");
}

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 520,
    height: 640,
    minWidth: 420,
    minHeight: 520,
    resizable: true,
    maximizable: false,
    title: "Isaac Ranked",
    autoHideMenuBar: true,
    backgroundColor: "#1a1a1a",
    webPreferences: {
      preload: join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  void mainWindow.loadFile(resolveUiPath());

  mainWindow.on("closed", () => {
    mainWindow = null;
  });
}

function sendStatus(payload: unknown): void {
  mainWindow?.webContents.send("launcher:status", payload);
}

function sendUpdateStatus(event: UpdateStatusEvent): void {
  mainWindow?.webContents.send("launcher:update", event);
}

async function runStartupUpdateCheck(): Promise<void> {
  const updated = await checkAndApplyLauncherUpdates({
    isPackaged: app.isPackaged,
    onStatus: sendUpdateStatus,
  });

  if (updated && !app.isPackaged) {
    app.relaunch();
    app.quit();
  }
}

ipcMain.handle("launcher:play", async () => {
  if (sessionRunning) {
    return { ok: false, error: "A session is already running." };
  }

  sessionRunning = true;
  sendStatus({ phase: "idle", message: "Starting..." });

  try {
    const exitCode = await runLaunchSession({
      onStatus(event: LaunchStatusEvent) {
        sendStatus(event);
      },
    });

    quittingAfterSession = true;
    sendStatus({
      phase: "done",
      message: "Isaac closed. Shutting down launcher...",
    });

    setTimeout(() => {
      app.quit();
    }, 400);

    return { ok: true, exitCode, quitting: true };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    sendStatus({ phase: "error", message, level: "error" });
    return { ok: false, error: message };
  } finally {
    sessionRunning = false;
    if (!quittingAfterSession) {
      sendStatus({ phase: "idle", message: "Ready to play." });
    }
  }
});

ipcMain.handle("launcher:open-config-dir", async () => {
  const configDir = process.env.ISAAC_RANKED_CONFIG_DIR ?? app.getPath("userData");
  await shell.openPath(configDir);
  return configDir;
});

app.whenReady().then(() => {
  configurePackagedPaths();
  createWindow();
  void runStartupUpdateCheck();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});
