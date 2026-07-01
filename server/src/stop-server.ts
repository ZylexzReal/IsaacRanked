import { execSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const WS_PORT = Number(process.env.ISAAC_RANKED_WS_PORT ?? 8765);
const HTTP_PORT = Number(process.env.ISAAC_RANKED_HTTP_PORT ?? 8766);
const SERVER_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "..");

function sleep(ms: number): void {
  runSafe(`powershell -NoProfile -Command "Start-Sleep -Milliseconds ${ms}"`);
}

function runSafe(command: string): string {
  try {
    return execSync(command, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
  } catch {
    return "";
  }
}

function findPidsOnPort(port: number): number[] {
  const pids = new Set<number>();
  const output = runSafe("netstat -ano -p tcp");
  const portSuffix = `:${port}`;

  for (const line of output.split(/\r?\n/)) {
    if (!line.includes("LISTENING")) continue;

    const parts = line.trim().split(/\s+/);
    const localAddress = parts[1] ?? "";
    if (!localAddress.endsWith(portSuffix)) continue;

    const pid = Number(parts.at(-1));
    if (Number.isFinite(pid) && pid > 0) {
      pids.add(pid);
    }
  }

  return [...pids];
}

function findWatchPids(): number[] {
  const pids = new Set<number>();
  const markers = [
    "tsx watch src/index.ts",
    "tsx watch src\\index.ts",
    "isaac-ranked-server",
  ];

  const output = runSafe(
    'powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \\"Name=\'node.exe\'\\" | Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress"'
  );

  if (!output) return [];

  try {
    const parsed = JSON.parse(output) as
      | { ProcessId: number; CommandLine?: string }
      | Array<{ ProcessId: number; CommandLine?: string }>;
    const processes = Array.isArray(parsed) ? parsed : [parsed];
    const selfPid = process.pid;

    for (const proc of processes) {
      if (proc.ProcessId === selfPid) continue;

      const commandLine = (proc.CommandLine ?? "").toLowerCase();
      const inServerDir = commandLine.includes(SERVER_DIR.toLowerCase());
      const matchesMarker = markers.some((marker) => commandLine.includes(marker.toLowerCase()));

      if (inServerDir && matchesMarker) {
        pids.add(proc.ProcessId);
      }
    }
  } catch {
    return [];
  }

  return [...pids];
}

function killPid(pid: number, withTree = false): boolean {
  try {
    const treeFlag = withTree ? " /T" : "";
    execSync(`taskkill /PID ${pid} /F${treeFlag}`, { stdio: "ignore" });
    console.log(`[stop] Stopped process ${pid}`);
    return true;
  } catch {
    return false;
  }
}

function portsInUse(): number[] {
  const busy: number[] = [];
  if (findPidsOnPort(WS_PORT).length > 0) busy.push(WS_PORT);
  if (findPidsOnPort(HTTP_PORT).length > 0) busy.push(HTTP_PORT);
  return busy;
}

function main(): number {
  const portPids = new Set([...findPidsOnPort(WS_PORT), ...findPidsOnPort(HTTP_PORT)]);
  const watchPids = new Set(findWatchPids());

  if (portPids.size === 0 && watchPids.size === 0) {
    console.log(`[stop] No Isaac Ranked server found on ports ${WS_PORT}/${HTTP_PORT}.`);
    return 0;
  }

  let stoppedAny = false;

  for (const pid of portPids) {
    stoppedAny = killPid(pid) || stoppedAny;
  }

  sleep(300);

  for (const pid of watchPids) {
    stoppedAny = killPid(pid, true) || stoppedAny;
  }

  sleep(300);

  const stillBusy = portsInUse();
  if (stillBusy.length > 0) {
    console.error(`[stop] Ports still in use: ${stillBusy.join(", ")}`);
    console.error("[stop] Close the terminal running `npm run dev`, then run stop again.");
    return 1;
  }

  if (stoppedAny) {
    console.log("[stop] Server stopped.");
    return 0;
  }

  console.error("[stop] Could not stop the server.");
  return 1;
}

process.exit(main());
