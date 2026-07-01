# Isaac Ranked — Oracle Cloud VPS deployment

Deploy the **matchmaking server** on Oracle Cloud. Players only subscribe to the mod on Steam Workshop — no command line, no local bridge agent.

## Architecture

```
Steam Workshop player                    Oracle Cloud VPS
┌─────────────────────────┐             ┌──────────────────────────┐
│ Isaac + Isaac Ranked    │             │ isaac-ranked-server      │
│   Repentogon Http API   │── HTTP POST │  WS matchmaking :8765    │
│   (PostSync /bridge)    │────────────▶│  HTTP bridge    :8766    │
└─────────────────────────┘             └──────────────────────────┘
```

Before publishing to Workshop, set your VPS hostname in `isaac-mod/scripts/config.lua`:

```lua
Config.MATCHMAKING_SERVER_HOST = "203.0.113.10"  -- your Oracle public IP or domain
Config.MATCHMAKING_SERVER_PORT = 8766
```

---

## Part 1 — Oracle Cloud VPS (server admin)

### 1. Create a compute instance

1. [Oracle Cloud Console](https://cloud.oracle.com/) → **Compute → Instances → Create**
2. Image: **Ubuntu 22.04** or **24.04**
3. Shape: Ampere A1 (Always Free) or 1 OCPU / 2 GB RAM
4. Add SSH key, note the **public IP**

### 2. Open port 8766

**Networking → VCN → Security Lists → Ingress rule:**

| Field | Value |
|-------|-------|
| Protocol | TCP |
| Port | 8766 |
| Source | `0.0.0.0/0` (or restrict to known IPs) |

Do **not** expose port **8765** publicly (internal WebSocket only).

If Ubuntu firewall is enabled:

```bash
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 8766 -j ACCEPT
sudo netfilter-persistent save
```

### 3. Install Node.js and the server

```bash
ssh ubuntu@YOUR_VPS_IP

curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs git

git clone https://github.com/YOUR_USER/IsaacRanked.git
cd IsaacRanked/server
npm ci
npm run build

cp .env.example .env
nano .env
```

`.env` contents:

```env
ISAAC_RANKED_DISABLE_LOG_BRIDGE=1
ISAAC_RANKED_HTTP_PORT=8766
ISAAC_RANKED_WS_PORT=8765
NODE_ENV=production
```

Test:

```bash
export $(grep -v '^#' .env | xargs)
npm start
```

From your PC:

```bash
curl http://YOUR_VPS_IP:8766/health
```

Expected: `{"ok":true,"bridgeDir":"..."}`

### 4. Run as a systemd service

```bash
sudo cp ~/IsaacRanked/deploy/isaac-ranked.service /etc/systemd/system/
# Edit User= and WorkingDirectory= if your paths differ
sudo systemctl daemon-reload
sudo systemctl enable --now isaac-ranked
journalctl -u isaac-ranked -f
```

---

## Part 2 — Steam Workshop (players)

Players install three things:

1. **REPENTOGON** — [repentogon.com/install.html](https://repentogon.com/install.html)
2. **Isaac Ranked mod** — Steam Workshop (enable in mod menu)
3. **Isaac Ranked Launcher** — download from your GitHub Releases (or ship `Play Isaac Ranked.cmd` + `launcher/` folder)

### Player steps

1. Subscribe to Isaac Ranked on Workshop
2. Install the launcher (one-time download)
3. Double-click **Play Isaac Ranked** in the launcher folder
4. In Isaac, press **F6** → **Queue Ranked**

No command line, npm, or bridge scripts required.

The launcher runs the ranked bridge automatically and launches Isaac.

See [`launcher/README.md`](../launcher/README.md) for launcher configuration.

### Before you publish the launcher

Set your VPS host in `launcher/config.default.json` (and ship that as `config.json` in releases):

```json
{
  "matchmakingHost": "YOUR_ORACLE_PUBLIC_IP",
  "matchmakingPort": 8766
}
```

---

## Part 3 — Local development (you only)

**Option A — Launcher + local server** (matches player experience):

1. `launcher/config.json` → `"matchmakingHost": "127.0.0.1"`
2. `npm run dev` in `server/`
3. `npm run play` in `launcher/` (or `Play Isaac Ranked.cmd`)

**Option B — Dev without launcher:**

1. Set `Config.USE_LAUNCHER_BRIDGE = false` in `isaac-mod/scripts/config.lua`
2. `Config.BRIDGE_HTTP_HOST = "127.0.0.1"`
3. `npm run dev` in `server/`
4. Install mod with `scripts/install-mod.ps1`
5. Launch Isaac normally

---

## Environment variables (server)

| Variable | Default | Description |
|----------|---------|-------------|
| `ISAAC_RANKED_DISABLE_LOG_BRIDGE` | unset | Set to `1` on VPS |
| `ISAAC_RANKED_HTTP_PORT` | `8766` | Client-facing HTTP bridge |
| `ISAAC_RANKED_WS_PORT` | `8765` | Internal WebSocket |

---

## Checklist

- [ ] VPS running Ubuntu with Node 20
- [ ] Port **8766** open in Oracle security list
- [ ] `ISAAC_RANKED_DISABLE_LOG_BRIDGE=1` on VPS
- [ ] `curl http://VPS_IP:8766/health` returns `ok: true`
- [ ] `launcher/config.default.json` points at your VPS IP
- [ ] Launcher release uploaded for players

---

## Security notes

- Traffic is plain HTTP today. Add nginx/Caddy + HTTPS on the VPS for production.
- Ratings are in-memory until persistent storage is added.
- Restrict port 8766 in the security list when possible.
