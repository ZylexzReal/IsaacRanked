# Isaac Ranked Launcher

Official launcher for ranked play. It:

1. Finds your Isaac + Isaac Ranked mod install (Steam / Workshop)
2. Starts the ranked bridge in the background (log → your matchmaking server)
3. Launches Isaac via Repentogon (enables Repentogon **Stealth Mode** automatically so the game starts without the Repentogon launcher window)
4. Stops the bridge when you close the game

Players do **not** need Node, npm, or PowerShell.

## Player setup

1. Install [REPENTOGON](https://repentogon.com/install.html)
2. Subscribe to **Isaac Ranked** on Steam Workshop and enable it
3. Download the launcher from releases (or clone this repo)
4. Edit `config.json` if needed (usually ships preconfigured with the official server)
5. Double-click **Play Isaac Ranked.cmd** (or run `npm run play` from `launcher/`)

## Configuration

`launcher/config.json`:

```json
{
  "matchmakingHost": "203.0.113.10",
  "matchmakingPort": 8766,
  "repentogonLauncherPath": "C:/path/to/REPENTOGONLauncher/REPENTOGONLauncher.exe"
}
```

`repentogonLauncherPath` is optional — the launcher auto-detects common install locations (including `Downloads/REPENTOGONLauncher/`). Set it only if auto-detect fails.

Use your Oracle VPS public IP or domain for production. For local dev, use `127.0.0.1` and run `npm run dev` in `server/`.

**Important:** `config.json` overrides `config.default.json`. If you had connection errors to `ranked.example.com`, delete or fix `config.json`.

- `ISAAC_RANKED_MATCHMAKING_HOST`
- `ISAAC_RANKED_HTTP_PORT`

## Development

```bash
cd launcher
npm install
npm run play
```

For local server testing, set `config.json` host to `127.0.0.1` and run `npm run dev` in `server/`.

## Building

```bash
cd launcher
npm install
npm run build
npm start
```

Future: package as `IsaacRankedLauncher.exe` with `pkg` or similar for GitHub Releases.

## How it works

```
Launcher → bridge (background) → VPS :8766/bridge
Isaac mod → log.txt [BRIDGE_SEND] → bridge → writes bridge_inbox.lua → mod reads response
```

The mod sets `Config.USE_LAUNCHER_BRIDGE = true` so it always uses the log bridge transport; the launcher forwards to your remote server.
