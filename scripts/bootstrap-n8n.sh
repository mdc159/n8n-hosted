#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script for DigitalOcean droplet:
# - Installs Docker + compose plugin
# - Enables UFW (22/80/443)
# - Copies deployment files into /opt/n8n
# - Generates a .env with random secrets and your inputs
# - Brings up the stack and enables the systemd unit
#
# Run as root on the droplet from the repo root:
#   sudo bash scripts/bootstrap-n8n.sh

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
DEST_DIR="/opt/n8n"

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run as root (sudo bash scripts/bootstrap-n8n.sh)" >&2
    exit 1
  fi
}

apt_install() {
  apt-get update
  apt-get install -y ca-certificates curl gnupg

  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  fi

  if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
    local codename
    codename="$(. /etc/os-release && echo "$UBUNTU_CODENAME")"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" \
      > /etc/apt/sources.list.d/docker.list
  fi

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin ufw
}

install_nodejs() {
  # Check if Node.js is already installed with sufficient version
  if command -v node &>/dev/null; then
    local version
    version=$(node -v | sed 's/v//' | cut -d. -f1)
    if [[ "${version}" -ge 18 ]]; then
      echo "Node.js $(node -v) already installed, skipping..."
      return 0
    fi
  fi

  echo "Installing Node.js 20.x LTS..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
}

setup_firewall() {
  ufw allow 22/tcp
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw --force enable
}

prompt_inputs() {
  read -rp "Domain for n8n (default n8n.pimpshizzle.com): " DOMAIN
  DOMAIN=${DOMAIN:-n8n.pimpshizzle.com}

  read -rp "Admin email for ACME (Let's Encrypt): " CADDY_EMAIL
  CADDY_EMAIL=${CADDY_EMAIL:-admin@example.com}

  read -rp "Caddy basic auth username [admin]: " BASIC_AUTH_USER
  BASIC_AUTH_USER=${BASIC_AUTH_USER:-admin}

  read -rsp "Caddy basic auth password (will be hashed): " BASIC_AUTH_PASSWORD
  echo

  read -rp "n8n basic auth username (optional, empty to skip): " N8N_BASIC_AUTH_USER
  if [[ -n "${N8N_BASIC_AUTH_USER}" ]]; then
    read -rsp "n8n basic auth password: " N8N_BASIC_AUTH_PASSWORD
    echo
  else
    N8N_BASIC_AUTH_PASSWORD=""
  fi
}

generate_secrets() {
  N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
  N8N_USER_MANAGEMENT_JWT_SECRET=$(openssl rand -hex 32)
  MCP_AUTH_TOKEN=$(openssl rand -hex 32)

  # Use caddy container to hash password so caddy binary isn't required on host
  BASIC_AUTH_HASH=$(docker run --rm caddy:2 caddy hash-password --plaintext "${BASIC_AUTH_PASSWORD}")
}

install_claude_code() {
  # Check if already installed
  if command -v claude &>/dev/null; then
    echo "Claude Code CLI already installed ($(claude --version 2>/dev/null || echo 'unknown version')), skipping..."
    return 0
  fi

  echo "Installing Claude Code CLI..."
  npm install -g @anthropic-ai/claude-code

  # Setup MCP configuration for root user (who runs the bootstrap)
  local config_dir="/root/.config/Claude"
  mkdir -p "${config_dir}"

  if [[ -f "${DEST_DIR}/claude-code.mcp.json" ]]; then
    cp "${DEST_DIR}/claude-code.mcp.json" "${config_dir}/claude_desktop_config.json"
    echo "MCP config installed to ${config_dir}/claude_desktop_config.json"
  fi
}

prepare_dirs() {
  mkdir -p "${DEST_DIR}"
  mkdir -p "${DEST_DIR}/videos"

  rsync -av --delete --exclude 'videos/' --exclude 'docker-compose.override.yml' \
    "${SRC_DIR}/docker-compose.yml" \
    "${SRC_DIR}/Dockerfile.n8n" \
    "${SRC_DIR}/Caddyfile" \
    "${SRC_DIR}/env.example" \
    "${SRC_DIR}/n8n-stack.service" \
    "${SRC_DIR}/claude-code.mcp.json" \
    "${SRC_DIR}/README.md" \
    "${DEST_DIR}/"

  # Ensure videos dir still exists after rsync (excluded above for safety)
  mkdir -p "${DEST_DIR}/videos"

  # Set ownership for videos directory (node user is UID 1000 inside container)
  chown -R 1000:1000 "${DEST_DIR}/videos"
}

write_env() {
  local env_file="${DEST_DIR}/.env"
  if [[ -f "${env_file}" ]]; then
    cp "${env_file}" "${env_file}.bak.$(date +%Y%m%d%H%M%S)"
  fi

  cat > "${env_file}" <<EOF
# Required secrets
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_USER_MANAGEMENT_JWT_SECRET=${N8N_USER_MANAGEMENT_JWT_SECRET}

# Domain / HTTPS
N8N_HOST=${DOMAIN}
WEBHOOK_URL=https://${DOMAIN}/
CADDY_EMAIL=${CADDY_EMAIL}
TZ=UTC

# Caddy basic auth (option A)
BASIC_AUTH_USER=${BASIC_AUTH_USER}
BASIC_AUTH_HASH=${BASIC_AUTH_HASH}

# Optional n8n settings (internal basic auth)
N8N_BASIC_AUTH_ACTIVE=$( [[ -n "${N8N_BASIC_AUTH_USER}" ]] && echo true || echo false )
N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
N8N_LOG_LEVEL=info

# MCP authentication (required for HTTP mode)
MCP_AUTH_TOKEN=${MCP_AUTH_TOKEN}

# MCP management tools (enables workflow CRUD via Claude Code CLI)
# After n8n is running, generate API key from: Settings > n8n API > Create API Key
# Then uncomment N8N_API_KEY and add your key
N8N_API_URL=http://n8n:5678
#N8N_API_KEY=your-n8n-api-key-here
EOF
}

bring_up_stack() {
  pushd "${DEST_DIR}" >/dev/null
  docker compose build --pull  # Build custom n8n image and pull latest base images
  docker compose up -d
  popd >/dev/null
}

enable_systemd() {
  cp "${DEST_DIR}/n8n-stack.service" /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now n8n-stack
}

main() {
  require_root
  apt_install
  install_nodejs
  setup_firewall
  prompt_inputs
  generate_secrets
  prepare_dirs
  write_env
  bring_up_stack
  enable_systemd
  install_claude_code

  echo ""
  echo "=========================================="
  echo "Done. Visit: https://${DOMAIN}"
  echo "=========================================="
  echo "Caddy basic auth user: ${BASIC_AUTH_USER}"
  [[ -n "${N8N_BASIC_AUTH_USER}" ]] && echo "n8n basic auth user: ${N8N_BASIC_AUTH_USER}"
  echo "Env saved to ${DEST_DIR}/.env (backup if existed)."
  echo ""
  echo "Claude Code CLI installed. Run 'claude' to start."
  echo "MCP config: /root/.config/Claude/claude_desktop_config.json"
  echo ""
  echo "Videos folder: ${DEST_DIR}/videos"
  echo "FFmpeg available in n8n container: docker compose exec n8n ffmpeg -version"
}

main "$@"

