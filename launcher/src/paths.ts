import { existsSync, readFileSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { findRepentogonLauncher } from "./repentogon.js";

const ISAAC_APP_ID = "250900";
const MOD_FOLDER_NAMES = ["isaac-ranked"];

export interface LauncherPaths {
  gameRoot: string;
  modDir: string;
  logPath: string;
  isaacExecutable: string;
  repentogonLauncher: string;
  bridgeDir: string;
}

export interface LauncherConfig {
  matchmakingHost: string;
  matchmakingPort: number;
  repentogonLauncherPath?: string;
}

function normalize(path: string): string {
  return path.replace(/\\/g, "/");
}

function readSteamLibraryPaths(): string[] {
  const roots = new Set<string>();

  const defaults = [
    "C:/Program Files (x86)/Steam",
    "C:/Program Files/Steam",
    "D:/SteamLibrary",
    "E:/SteamLibrary",
    join(homedir(), "SteamLibrary"),
  ];

  for (const root of defaults) {
    if (existsSync(root)) {
      roots.add(normalize(root));
    }
  }

  for (const root of [...roots]) {
    const vdfPath = join(root, "steamapps", "libraryfolders.vdf");
    if (!existsSync(vdfPath)) {
      continue;
    }

    const content = readFileSync(vdfPath, "utf8");
    for (const pathMatch of content.matchAll(/"path"\s+"([^"]+)"/g)) {
      const libraryPath = pathMatch[1]?.replace(/\\\\/g, "/");
      if (libraryPath && existsSync(libraryPath)) {
        roots.add(normalize(libraryPath));
      }
    }
  }

  return [...roots];
}

function findGameRoot(libraryPaths: string[]): string | null {
  for (const library of libraryPaths) {
    const candidate = join(library, "steamapps", "common", "The Binding of Isaac Rebirth");
    if (existsSync(join(candidate, "isaac-ng.exe")) || existsSync(join(candidate, "Repentogon"))) {
      return candidate;
    }
  }
  return null;
}

function metadataMatches(content: string): boolean {
  const lower = content.toLowerCase();
  return lower.includes("<directory>isaac-ranked</directory>")
    || lower.includes("<name>isaac ranked</name>")
    || lower.includes("isaac-ranked");
}

function findModInDirectory(parentDir: string): string | null {
  if (!existsSync(parentDir)) {
    return null;
  }

  for (const folderName of MOD_FOLDER_NAMES) {
    const direct = join(parentDir, folderName);
    if (existsSync(join(direct, "main.lua"))) {
      return direct;
    }
  }

  for (const entry of readdirSync(parentDir, { withFileTypes: true })) {
    if (!entry.isDirectory()) {
      continue;
    }

    const modPath = join(parentDir, entry.name);
    if (!existsSync(join(modPath, "main.lua"))) {
      continue;
    }

    const metadataPath = join(modPath, "metadata.xml");
    if (existsSync(metadataPath)) {
      const metadata = readFileSync(metadataPath, "utf8");
      if (metadataMatches(metadata)) {
        return modPath;
      }
    }

    if (entry.name.toLowerCase().includes("isaac-ranked")) {
      return modPath;
    }
  }

  return null;
}

function findModDir(gameRoot: string, libraryPaths: string[]): string | null {
  for (const folder of ["mods", "Mods"]) {
    const fromGame = findModInDirectory(join(gameRoot, folder));
    if (fromGame) {
      return fromGame;
    }
  }

  for (const library of libraryPaths) {
    const workshopRoot = join(library, "steamapps", "workshop", "content", ISAAC_APP_ID);
    const fromWorkshop = findModInDirectory(workshopRoot);
    if (fromWorkshop) {
      return fromWorkshop;
    }
  }

  return null;
}

function findDocumentsRoot(): string | null {
  const bases = [
    join(homedir(), "Documents", "My Games"),
    join(homedir(), "OneDrive", "Documents", "My Games"),
  ];

  if (process.env.OneDrive) {
    bases.push(join(process.env.OneDrive, "Documents", "My Games"));
  }

  for (const base of bases) {
    const saveRoot = join(base, "Binding of Isaac Repentance+");
    if (existsSync(saveRoot)) {
      return saveRoot;
    }
  }

  return null;
}

function findVanillaIsaacExecutable(gameRoot: string): string | null {
  const vanilla = join(gameRoot, "isaac-ng.exe");
  if (existsSync(vanilla)) {
    return vanilla;
  }
  return null;
}

export function resolveLauncherPaths(config?: Pick<LauncherConfig, "repentogonLauncherPath">): LauncherPaths {
  const libraryPaths = readSteamLibraryPaths();
  const gameRoot = findGameRoot(libraryPaths);
  if (!gameRoot) {
    throw new Error("Could not find The Binding of Isaac: Repentance+. Install it on Steam first.");
  }

  const modDir = findModDir(gameRoot, libraryPaths);
  if (!modDir) {
    throw new Error(
      "Could not find the Isaac Ranked mod. Subscribe on Steam Workshop and enable it in the mod menu.",
    );
  }

  const documentsRoot = findDocumentsRoot();
  if (!documentsRoot) {
    throw new Error("Could not find Isaac save data folder (Documents/My Games/Binding of Isaac Repentance+).");
  }

  const isaacExecutable = findVanillaIsaacExecutable(gameRoot);
  if (!isaacExecutable) {
    throw new Error(
      "Could not find isaac-ng.exe in your Isaac install. Verify the game is installed through Steam.",
    );
  }

  const repentogonLauncher = findRepentogonLauncher(gameRoot, config?.repentogonLauncherPath);

  return {
    gameRoot,
    modDir,
    logPath: join(documentsRoot, "log.txt"),
    isaacExecutable,
    repentogonLauncher,
    bridgeDir: join(documentsRoot, "isaac-ranked-bridge"),
  };
}

export function buildRemoteBridgeUrl(config: LauncherConfig): string {
  const host = config.matchmakingHost.trim().replace(/\/+$/, "");
  const port = config.matchmakingPort;
  if (host.startsWith("http://") || host.startsWith("https://")) {
    return `${host.replace(/\/bridge$/, "")}/bridge`;
  }
  return `http://${host}:${port}/bridge`;
}
