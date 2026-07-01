import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { join } from "node:path";

const execFileAsync = promisify(execFile);

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

async function listRepentogonIsaacPids(gameRoot: string): Promise<number[]> {
  const repentogonExe = join(gameRoot, "Repentogon", "isaac-ng.exe");
  const script = [
    "$exe = $env:REPENTOGON_EXE",
    "$procs = Get-CimInstance Win32_Process -Filter \"Name='isaac-ng.exe'\" -ErrorAction SilentlyContinue",
    "if (-not $procs) { exit 0 }",
    "foreach ($proc in @($procs)) {",
    "  if ($proc.ExecutablePath -and ($proc.ExecutablePath -ieq $exe)) {",
    "    Write-Output $proc.ProcessId",
    "  }",
    "}",
  ].join("; ");

  try {
    const { stdout } = await execFileAsync(
      "powershell.exe",
      ["-NoProfile", "-Command", script],
      {
        env: { ...process.env, REPENTOGON_EXE: repentogonExe },
        windowsHide: true,
        timeout: 10_000,
      },
    );

    return stdout
      .split(/\r?\n/)
      .map((line) => Number.parseInt(line.trim(), 10))
      .filter((pid) => Number.isFinite(pid) && pid > 0);
  } catch {
    return [];
  }
}

function isProcessRunning(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export async function waitForNewRepentogonIsaac(
  gameRoot: string,
  knownPids: Set<number>,
  timeoutMs: number,
): Promise<number> {
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    const pids = await listRepentogonIsaacPids(gameRoot);
    const freshPid = pids.find((pid) => !knownPids.has(pid));
    if (freshPid !== undefined) {
      return freshPid;
    }
    await sleep(500);
  }

  throw new Error(
    "Repentogon did not start Isaac within 3 minutes. "
      + "Open REPENTOGONLauncher once manually and click Play to finish any pending updates.",
  );
}

export async function waitForProcessExit(pid: number): Promise<void> {
  while (isProcessRunning(pid)) {
    await sleep(1000);
  }
}

export async function snapshotRepentogonIsaacPids(gameRoot: string): Promise<Set<number>> {
  return new Set(await listRepentogonIsaacPids(gameRoot));
}
