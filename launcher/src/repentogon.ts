import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export function findRepentogonLauncher(gameRoot: string, configuredPath?: string): string {
  if (configuredPath && configuredPath.trim() !== "" && existsSync(configuredPath)) {
    return configuredPath;
  }

  if (process.env.REPENTOGON_LAUNCHER_PATH && existsSync(process.env.REPENTOGON_LAUNCHER_PATH)) {
    return process.env.REPENTOGON_LAUNCHER_PATH;
  }

  const candidates = [
    join(gameRoot, "REPENTOGONLauncher", "REPENTOGONLauncher.exe"),
    join(gameRoot, "REPENTOGONLauncher.exe"),
    join(homedir(), "Downloads", "REPENTOGONLauncher", "REPENTOGONLauncher.exe"),
    join(homedir(), "Desktop", "REPENTOGONLauncher", "REPENTOGONLauncher.exe"),
    join(homedir(), "Downloads", "REPENTOGONLauncher.exe"),
    join(homedir(), "REPENTOGONLauncher", "REPENTOGONLauncher.exe"),
    "C:/Program Files/REPENTOGONLauncher/REPENTOGONLauncher.exe",
    "C:/Program Files (x86)/REPENTOGONLauncher/REPENTOGONLauncher.exe",
  ];

  for (const candidate of candidates) {
    if (existsSync(candidate)) {
      return candidate;
    }
  }

  throw new Error(
    "Could not find REPENTOGONLauncher.exe. Install Repentogon from https://repentogon.com/install.html "
      + "and set repentogonLauncherPath in launcher/config.json if it is installed elsewhere.",
  );
}
