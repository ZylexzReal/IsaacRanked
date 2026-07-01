import { cpSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const launcherRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const outDir = join(launcherRoot, "dist", "launcher", "electron");

mkdirSync(outDir, { recursive: true });
cpSync(join(launcherRoot, "electron", "index.html"), join(outDir, "index.html"));
cpSync(join(launcherRoot, "electron", "renderer.js"), join(outDir, "renderer.js"));
