import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

function documentsMyGamesBases(): string[] {
  const bases = [
    join(homedir(), "Documents", "My Games"),
    join(homedir(), "OneDrive", "Documents", "My Games"),
  ];

  if (process.env.OneDrive) {
    bases.push(join(process.env.OneDrive, "Documents", "My Games"));
  }

  return bases;
}

export function resolveRepentogonIniPath(): string {
  for (const base of documentsMyGamesBases()) {
    const iniPath = join(base, "repentogon_launcher.ini");
    if (existsSync(iniPath)) {
      return iniPath;
    }
  }

  return join(homedir(), "Documents", "My Games", "repentogon_launcher.ini");
}

/** Ensures Repentogon launcher skips its window and launches Isaac immediately. */
export function ensureRepentogonStealthMode(iniPath: string): boolean {
  let content = existsSync(iniPath) ? readFileSync(iniPath, "utf8") : "";

  if (!/\[General\]/i.test(content)) {
    content = `[General]\n${content}`;
  }

  if (/^StealthMode\s*=\s*1\s*$/im.test(content)) {
    return false;
  }

  if (/^StealthMode\s*=/im.test(content)) {
    content = content.replace(/^StealthMode\s*=\s*\d+/im, "StealthMode = 1");
  } else if (/\[General\]/i.test(content)) {
    content = content.replace(/\[General\]\s*\r?\n/i, "[General]\nStealthMode = 1\n");
  } else {
    content = `[General]\nStealthMode = 1\n${content}`;
  }

  mkdirSync(dirname(iniPath), { recursive: true });
  writeFileSync(iniPath, content, "utf8");
  return true;
}
