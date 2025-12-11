# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains a production deployment configuration for n8n (workflow automation platform) running on DigitalOcean behind Caddy reverse proxy with TLS, plus an n8n-MCP server for Claude Code integration. The stack is designed to run on a single Ubuntu droplet at `/opt/n8n` with systemd service management.

## Architecture

**Three-service Docker Compose stack:**
- `caddy`: Reverse proxy with automatic HTTPS (Let's Encrypt), basic authentication, and compression
- `n8n`: Custom image (Dockerfile.n8n) based on n8nio/n8n:latest with FFmpeg for video processing
- `mcp`: n8n-MCP server (ghcr.io/czlonkowski/n8n-mcp:latest) bound to localhost:3030 for Claude Code CLI integration

**Key architectural decisions:**
- n8n is never directly exposed; all traffic goes through Caddy
- Caddy handles both HTTP->HTTPS redirect and basic auth before reaching n8n
- MCP server runs in HTTP mode inside Docker but only published to 127.0.0.1:3030
- Claude Code CLI connects via stdio mode by doing `docker exec` into the running MCP container
- Persistent data stored in Docker volumes: `n8n_data`, `caddy_data`, `caddy_config`, `mcp_data`
- Binary workflow data (large files) stored on filesystem for better performance
- Videos folder (`/opt/n8n/videos`) mounted for video processing workflows

**Environment configuration:**
- `.env` file drives all configuration (see `env.example` for template)
- bcrypt password hashes in `.env` require double-dollar escaping for Docker Compose (`$$2a$$14$$...`)
- Two auth layers possible: Caddy basic auth (required) and optional n8n internal auth

**Deployment model:**
- GitHub repo (`mdc159/n8n-hosted`) is source of truth
- Droplet uses SSH deploy key for git operations (no PATs)
- Deployment lives at `/opt/n8n` on the droplet
- systemd unit (`n8n-stack.service`) manages lifecycle

## Common Commands

### Initial deployment (from scratch on droplet)
```bash
# Bootstrap entire stack (as root)
sudo bash scripts/bootstrap-n8n.sh

# Manual setup alternative
git clone git@github.com:mdc159/n8n-hosted.git /opt/n8n
cd /opt/n8n
cp env.example .env
# Edit .env with secrets and domain
docker compose up -d
sudo cp n8n-stack.service /etc/systemd/system/
sudo systemctl enable --now n8n-stack
```

### Stack management
```bash
cd /opt/n8n
docker compose build --pull   # Rebuild custom n8n image with latest base
docker compose up -d          # Start stack
docker compose down           # Stop stack
docker compose logs -f caddy  # View Caddy logs
docker compose logs -f n8n    # View n8n logs
docker compose logs -f mcp    # View MCP logs
```

### FFmpeg and video operations
```bash
# Verify FFmpeg is available in n8n container
docker compose exec n8n ffmpeg -version

# List files in videos folder
docker compose exec n8n ls -la /home/node/videos

# Videos folder is also accessible on host at /opt/n8n/videos
ls -la /opt/n8n/videos
```

### Systemd service
```bash
sudo systemctl status n8n-stack    # Check status
sudo systemctl restart n8n-stack   # Restart all services
sudo systemctl stop n8n-stack      # Stop stack
sudo journalctl -u n8n-stack -f    # Follow service logs
```

### Caddy operations
```bash
# Reload Caddyfile after changes (no downtime)
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile

# Generate bcrypt hash for basic auth (when updating password)
docker run --rm caddy:2 caddy hash-password --plaintext 'YourPassword'
# Copy output to .env as BASIC_AUTH_HASH with $$ escaping
```

### Configuration updates
```bash
# After editing .env or Caddyfile
docker compose down && docker compose up -d

# After editing n8n-stack.service
sudo cp n8n-stack.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl restart n8n-stack
```

### Git operations (on droplet with deploy key)
```bash
cd /opt/n8n
GIT_SSH_COMMAND='ssh -i ~/.ssh/id_ed25519_n8n -o IdentitiesOnly=yes' git pull
GIT_SSH_COMMAND='ssh -i ~/.ssh/id_ed25519_n8n -o IdentitiesOnly=yes' git push
```

### MCP integration (on droplet host)
```bash
# Claude Code CLI is installed automatically by bootstrap script
# Manual installation if needed:
sudo npm install -g @anthropic-ai/claude-code

# Configure MCP connection (uses docker exec stdio)
mkdir -p ~/.config/Claude
cp /opt/n8n/claude-code.mcp.json ~/.config/Claude/claude_desktop_config.json

# Verify MCP container name matches config
docker ps | grep mcp
# Update claude-code.mcp.json if container name differs from n8n-stack-mcp-1
```

### MCP management tools (optional)
To enable MCP tools that can manage n8n workflows:
```bash
# 1. Log into n8n web UI
# 2. Navigate to Settings (gear icon) > n8n API
# 3. Click "Create API Key"
# 4. Add to .env:
echo 'N8N_API_URL=http://n8n:5678' >> /opt/n8n/.env
echo 'N8N_API_KEY=your-api-key-here' >> /opt/n8n/.env

# 5. Restart stack to apply
docker compose down && docker compose up -d
```

## Important Implementation Details

### Password handling
- Shell: Use single quotes for passwords with special chars when hashing: `caddy hash-password --plaintext 'Pass!123'`
- .env file: Escape bcrypt hashes with double dollars: `BASIC_AUTH_HASH=$$2a$$14$$xyz...`
- Docker Compose treats single `$` as variable interpolation; `$$` becomes literal `$`

### Security notes
- MCP port 3030 is bound to 127.0.0.1 only (not 0.0.0.0)
- Firewall rules: UFW allows only 22, 80, 443
- Caddy basic auth protects entire n8n UI
- n8n internal auth is optional (can add second layer)
- Never commit `.env` file (in `.gitignore`)

### TLS/HTTPS requirements
- n8n must run with `N8N_PROTOCOL=https` for OAuth callbacks
- Domain must point to droplet IP via A record
- Caddy auto-provisions Let's Encrypt cert for domain in `N8N_HOST`
- Webhook URLs use `WEBHOOK_URL=https://domain/`

### MCP connection modes
- MCP container runs in `MCP_MODE=http` (listens on port 3030)
- Claude Code CLI uses `MCP_MODE=stdio` via docker exec into container
- This allows local-only access without exposing HTTP endpoint publicly

### File locations on droplet
- Stack definition: `/opt/n8n/docker-compose.yml`
- Custom n8n image: `/opt/n8n/Dockerfile.n8n`
- Reverse proxy config: `/opt/n8n/Caddyfile`
- Environment: `/opt/n8n/.env` (generated from `env.example`)
- Systemd unit: `/etc/systemd/system/n8n-stack.service`
- MCP config template: `/opt/n8n/claude-code.mcp.json`
- SSH deploy key: `~/.ssh/id_ed25519_n8n`
- Videos folder: `/opt/n8n/videos` (bind mounted to container)

### Local testing files (not deployed to droplet)
- `docker-compose.override.yml` - Auto-loaded for local HTTP testing
- `Caddyfile.local` - Simple reverse proxy without TLS/auth
- `.env.local.example` - Template for local testing environment

### Required environment variables
Generate random secrets:
```bash
openssl rand -hex 32  # For N8N_ENCRYPTION_KEY
openssl rand -hex 32  # For N8N_USER_MANAGEMENT_JWT_SECRET
```

Must set in `.env`:
- `N8N_ENCRYPTION_KEY`, `N8N_USER_MANAGEMENT_JWT_SECRET` (32-char random hex)
- `N8N_HOST` (domain, e.g., n8n.pimpshizzle.com)
- `WEBHOOK_URL` (https://domain/)
- `CADDY_EMAIL` (for ACME notifications)
- `BASIC_AUTH_USER`, `BASIC_AUTH_HASH` (Caddy basic auth credentials)
- `TZ` (timezone, e.g., UTC)

Optional:
- `N8N_API_URL`, `N8N_API_KEY` (if using MCP management tools)
- `N8N_BASIC_AUTH_ACTIVE`, `N8N_BASIC_AUTH_USER`, `N8N_BASIC_AUTH_PASSWORD` (n8n internal auth)

## Testing and Verification

### Local testing (development)
```bash
# 1. Create local .env from template
cp .env.local.example .env

# 2. Build and start stack (override auto-applies)
docker compose build
docker compose up -d

# 3. Verify services
docker compose ps

# 4. Test FFmpeg
docker compose exec n8n ffmpeg -version

# 5. Test videos directory
docker compose exec n8n ls -la /home/node/videos

# 6. Access n8n UI (no auth in local mode)
open http://localhost:8080

# 7. Cleanup
docker compose down
```

### Production smoke test checklist
```bash
# Verify stack is running
docker compose ps

# Check TLS certificate
curl -I https://n8n.pimpshizzle.com
# Should show 401 (basic auth) with valid cert

# Test basic auth
curl -u admin:password https://n8n.pimpshizzle.com
# Should return n8n login page HTML

# Verify logs are clean
docker compose logs caddy --tail=50
docker compose logs n8n --tail=50
# Look for ACME success, no 502 errors

# Test MCP from CLI (if configured)
# Run Claude Code CLI and verify MCP tools like search_nodes work
```

### Common issues
- 502 Bad Gateway: n8n container not ready, check `docker compose logs n8n`
- ACME failure: DNS not pointing to droplet, check A record
- Basic auth loop: Hash escaping wrong in .env (needs `$$` not `$`)
- MCP connection fails: Container name mismatch in `claude-code.mcp.json`
- FFmpeg not found: Custom image not built, run `docker compose build --pull`
- Videos permission denied: Run `chown -R 1000:1000 /opt/n8n/videos` on host
