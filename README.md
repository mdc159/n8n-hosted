# DigitalOcean n8n + Caddy + n8n-MCP + Claude Code CLI

Archon Project ID=ec84cbfd-4324-46e9-a508-a9c2691ffb5c

Production deployment for n8n with FFmpeg video processing, behind Caddy TLS on `n8n.pimpshizzle.com`, with n8n-MCP server for Claude Code CLI integration.

## Features
- **n8n** workflow automation with custom Docker image
- **FFmpeg** for video processing in workflows
- **Filesystem binary mode** for handling large files
- **Persistent videos folder** at `/opt/n8n/videos`
- **Caddy** reverse proxy with automatic HTTPS (Let's Encrypt)
- **n8n-MCP** server for Claude Code CLI integration
- **Claude Code CLI** automated installation

## Prerequisites
- Domain: `n8n.pimpshizzle.com` pointing via A record to the droplet IP.
- Ubuntu CPU droplet (e.g., 2 vCPU / 4 GB). Recommended OS: Ubuntu 22.04 LTS (Jammy). 24.04 LTS is fine if you prefer latest, but 22.04 has the broadest Docker/docs support.
- SSH access as a sudo-capable user.
- GitHub access: prefer SSH deploy key on the droplet so it can `git pull`/`git push` to `mdc159/n8n-hosted` without PATs.
- Shell/env tips:
  - When hashing passwords with `!` or other special chars, wrap in single quotes: `caddy hash-password --plaintext 'Sturdy-N8n!93^Caddy'`.
  - In `.env`, escape bcrypt hashes with double dollars so compose doesn’t treat `$` as vars: `BASIC_AUTH_HASH=$$2a$$14$$...`.

### Set up droplet deploy key (SSH)
On the droplet (root):
```bash
ssh-keygen -t ed25519 -C "droplet-n8n" -f ~/.ssh/id_ed25519_n8n -N ""
install -d -m 700 ~/.ssh
cat > ~/.ssh/config <<'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_n8n
  IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config ~/.ssh/id_ed25519_n8n
chmod 644 ~/.ssh/id_ed25519_n8n.pub
cat ~/.ssh/id_ed25519_n8n.pub
```
In GitHub → repo → Settings → Deploy keys → Add deploy key → paste the pubkey → enable **Allow write** if you want to push from the droplet. Then verify:
```bash
ssh -i ~/.ssh/id_ed25519_n8n -o IdentitiesOnly=yes -T git@github.com
```
You should see “successfully authenticated.”

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
Clone on the droplet using the deploy key (recommended):
```bash
rm -rf /opt/n8n
GIT_SSH_COMMAND='ssh -i ~/.ssh/id_ed25519_n8n -o IdentitiesOnly=yes' \
  git clone git@github.com:mdc159/n8n-hosted.git /opt/n8n
cd /opt/n8n
```

If you cannot use GitHub from the droplet, you can `scp -r` the repo contents to `/opt/n8n`, but GitHub should remain the source of truth.

Files to have in `/opt/n8n`:
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
- `N8N_ENCRYPTION_KEY` (random 32 chars): `openssl rand -hex 32`
- `N8N_USER_MANAGEMENT_JWT_SECRET` (random 32 chars): `openssl rand -hex 32`
- `MCP_AUTH_TOKEN` (random 32 chars): `openssl rand -hex 32`
- `N8N_HOST=n8n.pimpshizzle.com`
- `WEBHOOK_URL=https://n8n.pimpshizzle.com/`
- `CADDY_EMAIL=you@example.com` (for ACME)
- `TZ=UTC`

Basic auth (Caddy):
- `BASIC_AUTH_USER=admin`
- Generate hash: `docker run --rm caddy:2 caddy hash-password --plaintext 'YourStrongPassword'`
- Set `BASIC_AUTH_HASH=<output>` (use `$$` escaping for `$` chars)

MCP management (optional - enables workflow CRUD via Claude Code):
- `N8N_API_URL=http://n8n:5678`
- `N8N_API_KEY=<generated from n8n UI: Settings > n8n API>`

## 5) Bring up the stack
```bash
cd /opt/n8n
docker compose build --pull  # Build custom n8n image with FFmpeg
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

## 13) FFmpeg and video operations
```bash
# Verify FFmpeg is available in n8n container
docker compose exec n8n ffmpeg -version

# List files in videos folder (from container)
docker compose exec n8n ls -la /home/node/videos

# Videos folder is also accessible on host
ls -la /opt/n8n/videos
```

## 14) Smoke test checklist
- `https://n8n.pimpshizzle.com` loads with valid cert and basic auth prompt.
- Sign in to n8n UI and run a sample workflow.
- FFmpeg works: `docker compose exec n8n ffmpeg -version`
- Claude Code CLI can call MCP tools (e.g., `search_nodes`) without errors.
- Caddy logs show ACME success and no 502s; n8n logs clean.

## 15) MCP capabilities with API key

| Feature | Without API Key | With API Key |
|---------|-----------------|--------------|
| List workflows | ✅ | ✅ |
| Search nodes | ✅ | ✅ |
| Create workflows | ❌ | ✅ |
| Update workflows | ❌ | ✅ |
| Activate/deactivate | ❌ | ✅ |
| Execute workflows | ❌ | ✅ |

## Local Development

For local testing without TLS:
```bash
cp .env.local.example .env
docker compose build
docker compose up -d
# Access at http://localhost:8080
```

