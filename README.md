# DigitalOcean n8n + Caddy + n8n-MCP + Claude Code CLI

Step-by-step to deploy n8n behind Caddy TLS on `n8n.pimpshizzle.com`, with a local-only n8n-MCP server and Claude Code CLI pointing to it.

## Prerequisites
- Domain: `n8n.pimpshizzle.com` pointing via A record to the droplet IP.
- Ubuntu CPU droplet (e.g., 2 vCPU / 4 GB). Recommended OS: Ubuntu 22.04 LTS (Jammy). 24.04 LTS is fine if you prefer latest, but 22.04 has the broadest Docker/docs support.
- SSH access as a sudo-capable user.

## 1) Firewall
```bash
sudo ufw allow 22 80 443
sudo ufw enable
```

## 2) Install Docker + compose
```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
curl -fsSL https://get.docker.com | sudo sh
sudo apt-get install -y docker-compose-plugin
sudo usermod -aG docker $USER
```
Re-login or `exec su - $USER` to pick up the docker group.

## 3) Stage deployment files
Copy these repo root files to `/opt/n8n` on the droplet:
- `docker-compose.yml`
- `Caddyfile`
- `env.example` (copy to `.env` and fill)
- `n8n-stack.service`
- `claude-code.mcp.json` (reference config for Claude Code CLI)

```bash
sudo mkdir -p /opt/n8n
sudo chown $USER:$USER /opt/n8n
cd /opt/n8n
cp env.example .env
```

## 4) Fill `.env`
Required:
- `N8N_ENCRYPTION_KEY` (random 32 chars)
- `N8N_USER_MANAGEMENT_JWT_SECRET` (random 32 chars)
- `N8N_HOST=n8n.pimpshizzle.com`
- `WEBHOOK_URL=https://n8n.pimpshizzle.com/`
- `CADDY_EMAIL=you@example.com` (for ACME)
- `TZ=UTC`

Basic auth (Caddy, option A):
- `BASIC_AUTH_USER=admin`
- Generate hash: `caddy hash-password --plaintext 'YourStrongPassword'`
- Set `BASIC_AUTH_HASH=<output>`

Optional (if you want MCP to manage n8n):
- `N8N_API_URL=http://n8n:5678`
- `N8N_API_KEY=<n8n API key>`

## 5) Bring up the stack
```bash
cd /opt/n8n
docker compose pull
docker compose up -d
```

## 6) Enable on boot (systemd)
```bash
sudo cp /opt/n8n/n8n-stack.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now n8n-stack
```

## 7) Verify TLS and basic auth
```bash
docker compose logs caddy --tail=50
curl -I https://n8n.pimpshizzle.com
```
Browser should prompt for basic auth (Caddy), then load n8n.

## 8) Claude Code CLI on the host
Install Node/npm and CLI:
```bash
sudo apt-get install -y nodejs npm
sudo npm install -g @anthropic-ai/claude-code
```
Configure CLI to use the MCP container via stdio (example uses service name `n8n-stack-mcp-1`):
```bash
mkdir -p ~/.config/Claude
cp /opt/n8n/claude-code.mcp.json ~/.config/Claude/claude_desktop_config.json
```
If the container name differs, update the `docker exec ...` line accordingly (`docker ps` to confirm).

## 9) Google OAuth readiness
- Keep `N8N_PROTOCOL=https` (set via compose).
- Redirect URI pattern: `https://n8n.pimpshizzle.com/rest/oauth2-credential/callback`
- Webhooks will use `WEBHOOK_URL=https://n8n.pimpshizzle.com/`

## 10) Local-only MCP
- MCP is bound to `127.0.0.1:3030` (published only on loopback).
- Use via Claude Code CLI on the host; not exposed publicly.

## 11) Common operations
- Logs: `docker compose logs -f caddy` or `docker compose logs -f n8n`
- Reload Caddy after Caddyfile changes: `docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile`
- Restart stack: `docker compose down && docker compose up -d`

## 12) Optional Git workspace
If you want to keep workflow artifacts under Git:
```bash
mkdir -p /opt/n8n/repo
cd /opt/n8n/repo
git init
```
Keep it separate from runtime volumes (`n8n_data`, `caddy_data`, `caddy_config`, `mcp_data`).

## 13) Smoke test checklist
- `https://n8n.pimpshizzle.com` loads with valid cert and basic auth prompt.
- Sign in to n8n UI and run a sample workflow.
- Claude Code CLI can call MCP tools (e.g., `search_nodes`) without errors.
- Caddy logs show ACME success and no 502s; n8n logs clean.

