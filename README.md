# Isaac Ranked

Ranked speedrunning mod for The Binding of Isaac (Repentogon) with matchmaking server and launcher.

## Components

| Folder | Description |
|--------|-------------|
| `isaac-mod/` | Repentogon mod (Steam Workshop) |
| `server/` | Matchmaking + bridge server (deploy to VPS) |
| `launcher/` | Player launcher (bridge + game start) |
| `deploy/` | VPS deployment docs and systemd service |

## Quick start (players)

1. Install [REPENTOGON](https://repentogon.com/install.html)
2. Subscribe to Isaac Ranked on Steam Workshop
3. Download the launcher and run **Play Isaac Ranked.cmd**

See [`launcher/README.md`](launcher/README.md).

## Server deployment

See [`deploy/oracle-cloud.md`](deploy/oracle-cloud.md).

## Development

```bash
cd server && npm install && npm run dev
cd launcher && npm install && npm run play
```
