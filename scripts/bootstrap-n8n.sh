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

  # Use caddy container to hash password so caddy binary isn't required on host
  BASIC_AUTH_HASH=$(docker run --rm caddy:2 caddy hash-password --plaintext "${BASIC_AUTH_PASSWORD}")
}

prepare_dirs() {
  mkdir -p "${DEST_DIR}"
  rsync -av --delete \
    "${SRC_DIR}/docker-compose.yml" \
    "${SRC_DIR}/Caddyfile" \
    "${SRC_DIR}/env.example" \
    "${SRC_DIR}/n8n-stack.service" \
    "${SRC_DIR}/claude-code.mcp.json" \
    "${SRC_DIR}/README.md" \
    "${DEST_DIR}/"
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

# Optional MCP management (if you want MCP to call n8n API)
#N8N_API_URL=http://n8n:5678
#N8N_API_KEY=
EOF
}

bring_up_stack() {
  pushd "${DEST_DIR}" >/dev/null
  docker compose pull
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
  setup_firewall
  prompt_inputs
  generate_secrets
  prepare_dirs
  write_env
  bring_up_stack
  enable_systemd

  echo "Done. Visit: https://${DOMAIN}"
  echo "Caddy basic auth user: ${BASIC_AUTH_USER}"
  [[ -n "${N8N_BASIC_AUTH_USER}" ]] && echo "n8n basic auth user: ${N8N_BASIC_AUTH_USER}"
  echo "Env saved to ${DEST_DIR}/.env (backup if existed)."
}

main "$@"

