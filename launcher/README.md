# Isaac Ranked Launcher

Official launcher for ranked play. It:

1. Finds your Isaac + Isaac Ranked mod install (Steam / Workshop)
2. Starts the ranked bridge in the background (log → your matchmaking server)
3. Launches Isaac via Repentogon (enables Repentogon **Stealth Mode** automatically)
4. Stops the bridge when you close the game

Players do **not** need Node, npm, or a visible command prompt.

## Player setup

1. Install [REPENTOGON](https://repentogon.com/install.html)
2. Subscribe to **Isaac Ranked** on Steam Workshop and enable it
3. Install **Isaac Ranked** from the release installer (`Isaac Ranked Setup.exe`)
4. Launch **Isaac Ranked** from the desktop shortcut
5. Click **Play Ranked**

For development from source, double-click **Play Isaac Ranked.cmd** in the repo root (opens the GUI with no CMD window).

## GUI launcher

The launcher is a small desktop app (Electron):

- **Play Ranked** — starts bridge + launches Isaac
- Live status log
- **Open config folder** — edit `config.json` (server IP, etc.)

No command window is shown when using the installed app or `Play Isaac Ranked.vbs`.

## Configuration

Installed app stores config at:

`%APPDATA%/isaac-ranked-launcher/config.json`

(Use **Open config folder** in the launcher UI.)

```json
{
  "matchmakingHost": "134.98.150.221",
  "matchmakingPort": 8766,
  "repentogonLauncherPath": "C:/path/to/REPENTOGONLauncher/REPENTOGONLauncher.exe"
}
```

`repentogonLauncherPath` is optional — auto-detects common install locations.

For local dev, edit `launcher/config.json` and use `127.0.0.1` with `npm run dev` in `server/`.

## Development

```bash
cd launcher
npm install
npm run gui
```

CLI-only (debug):

```bash
npm run play
```

## Building the installer (Windows)

```bash
cd launcher
npm install
npm run dist
```

Output:

- `launcher/release/Isaac Ranked Setup x.x.x.exe` — give this to players
- `launcher/release/win-unpacked/` — portable build for testing

The installer creates desktop + Start Menu shortcuts. Players only need the `.exe` installer, not Node or npm.

## Auto-updates

On startup the launcher checks [launcher/package.json on GitHub](https://github.com/ZylexzReal/IsaacRanked/tree/main/launcher) for a newer version.

| Install type | What happens |
|--------------|--------------|
| **Installed app** (`.exe`) | Downloads the latest [GitHub Release](https://github.com/ZylexzReal/IsaacRanked/releases) installer and restarts |
| **Dev / git clone** | Runs `git pull`, `npm install`, and `npm run build`, then restarts |

Publish updates:

1. Bump `version` in `launcher/package.json`
2. Commit and push to `main`
3. Run `npm run dist` and upload `launcher/release/Isaac Ranked Setup x.x.x.exe` to a GitHub Release tagged `vX.Y.Z`

## Session behavior

When Isaac closes, the launcher **exits automatically** (no background CMD or bridge left running). Launch it again to play another run.


```
Launcher → bridge (background) → VPS :8766/bridge
Isaac mod → log.txt [BRIDGE_SEND] → bridge → writes bridge_inbox.lua → mod reads response
```

The mod sets `Config.USE_LAUNCHER_BRIDGE = true` so it always uses the log bridge transport; the launcher forwards to your remote server.
