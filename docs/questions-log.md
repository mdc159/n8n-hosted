# Session Q&A log

Chronological notes of user questions and answers to aid future automation/scripting.

- Basic auth in front of n8n: explained Caddy option (basicauth) and n8n built-in option; implemented Caddy basicauth using env-driven user/hash.
- README request: produced step-by-step deployment guide (DNS, Docker, compose, Caddy, MCP, Claude CLI, OAuth, smoke tests) and noted Ubuntu 22.04 LTS recommended (24.04 acceptable).
- Git setup: initialized repo, added .gitignore, confirmed push to `github.com/mdc159/n8n-hosted` on branch `main`.
- Secrets guidance: provided methods to generate `N8N_ENCRYPTION_KEY`, `N8N_USER_MANAGEMENT_JWT_SECRET`, and example strong passwords; advised keeping `.env` out of git.
- SSH config: added `~/.ssh/config` host `n8n-droplet` (HostName 143.110.140.89, User root, IdentityFile ~/.ssh/id_ed25519).
- Droplet package prompts: ok to restart `unattended-upgrades.service`; for Docker GPG key prompt, keep existing key (answer `n` or cancel) and continue install.
- Docker install steps: documented apt repo add and install commands for Docker CE + compose plugin, group membership, and verification.
- Deploy key lessons: use a droplet-specific SSH key (`~/.ssh/id_ed25519_n8n`), add as GitHub deploy key (allow write if pushing), set `~/.ssh/config` with `IdentitiesOnly yes`, chmod 600 on key/config, verify with `ssh -i ~/.ssh/id_ed25519_n8n -o IdentitiesOnly=yes -T git@github.com`, and clone with `GIT_SSH_COMMAND='ssh -i ~/.ssh/id_ed25519_n8n -o IdentitiesOnly=yes' git clone git@github.com:mdc159/n8n-hosted.git /opt/n8n`.
- Auth + env quirks:
  - When hashing passwords containing `!`, wrap in single quotes to avoid shell expansion: `caddy hash-password --plaintext 'Sturdy-N8n!93^Caddy'`.
  - In `.env`, escape bcrypt hashes with `$$` so docker-compose doesn’t treat `$` as env vars (e.g., `BASIC_AUTH_HASH=$$2a$$14$$...`).
  - Ensure Caddy receives BASIC_AUTH_USER/HASH via compose env so auth works; after changes, recreate the stack.

