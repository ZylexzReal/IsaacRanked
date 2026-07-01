const playBtn = document.getElementById("playBtn");
const logEl = document.getElementById("log");
const statusText = document.getElementById("statusText");
const statusDot = document.getElementById("statusDot");
const configBtn = document.getElementById("configBtn");

if (!(playBtn instanceof HTMLButtonElement)
  || !(logEl instanceof HTMLDivElement)
  || !(statusText instanceof HTMLSpanElement)
  || !(statusDot instanceof HTMLSpanElement)
  || !(configBtn instanceof HTMLButtonElement)) {
  throw new Error("Launcher UI failed to initialize.");
}

/** @type {import("./preload").} */
const api = window.isaacRanked;

function appendLog(message, level = "info") {
  const line = document.createElement("div");
  line.className = `log-line ${level}`;
  line.textContent = message;
  logEl.appendChild(line);
  logEl.scrollTop = logEl.scrollHeight;
}

function setBusy(busy) {
  playBtn.disabled = busy;
  statusDot.className = busy ? "dot busy" : "dot";
  statusText.textContent = busy ? "Running..." : "Ready to play";
}

api.onStatus((event) => {
  if (!event || typeof event !== "object") {
    return;
  }

  const payload = /** @type {{ message?: string; level?: string; phase?: string; serverOnline?: boolean }} */ (event);

  if (payload.message) {
    appendLog(payload.message, payload.level ?? "info");
  }

  if (payload.phase === "checking" && typeof payload.serverOnline === "boolean") {
    statusDot.className = payload.serverOnline ? "dot online" : "dot offline";
    statusText.textContent = payload.serverOnline ? "Server online" : "Server offline";
  }

  if (payload.phase === "launching" || payload.phase === "playing") {
    setBusy(true);
    statusText.textContent = "Isaac is running";
    statusDot.className = "dot busy";
  }

  if (payload.phase === "done" || payload.phase === "idle" || payload.phase === "error") {
    setBusy(false);
  }
});

api.onUpdate((event) => {
  if (!event || typeof event !== "object") {
    return;
  }

  const payload = /** @type {{ message?: string; level?: string }} */ (event);
  if (payload.message) {
    appendLog(payload.message, payload.level ?? "info");
  }
});

playBtn.addEventListener("click", async () => {
  logEl.textContent = "";
  setBusy(true);
  appendLog("Starting Isaac Ranked session...");

  const result = await api.play();
  if (result?.quitting) {
    return;
  }

  if (!result?.ok && result?.error) {
    appendLog(result.error, "error");
  }

  setBusy(false);
  statusText.textContent = "Ready to play";
  statusDot.className = "dot";
});

configBtn.addEventListener("click", () => {
  void api.openConfigDir();
});

appendLog("Click Play Ranked to start the bridge and launch Isaac.");
