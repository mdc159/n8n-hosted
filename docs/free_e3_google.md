Below is a **fully-rewritten, automation-friendly playbook** for hosting a **stable n8n instance on Google Cloud’s always-free E2-micro (30 GB PD)**.
It incorporates every lesson from our troubleshooting, replaces the ad-hoc YouTube steps with reproducible scripts, and highlights optional upgrades.

---

## 1. Why Debian 12 is the right base image

| Option                                           | Free-tier eligible?                         | Docker support                | Pros                                   | Cons                                                |                                   |
| ------------------------------------------------ | ------------------------------------------- | ----------------------------- | -------------------------------------- | --------------------------------------------------- | --------------------------------- |
| **Debian 12 “bookworm” (Google-provided image)** | **Yes** (us-west1 / us-central1 / us-east1) | First-class in Docker CE repo | Stable, small, same image Google tests | Slightly older kernel than Ubuntu                   |                                   |
| Ubuntu 22.04                                     | No in free-tier regions                     | First-class                   | Newer kernel & packages                | Costs $ if you leave free tier                      |                                   |
| Container-Optimized OS                           | Yes                                         | Built-in container runtime    | Ultra-light, automatic updates         | Read-only FS, no apt/SSH tinkering, complex certbot | ([Google Cloud Documentation][1]) |

Debian therefore gives you the free SKU **and** a normal apt-based workflow.

---

## 2. Top-level architecture

```
Internet ─▶ GCP VPC ─▶ Firewall (80/443) ─▶ Nginx reverse proxy (VM) ─▶ n8n (Docker, port 5678)
           │              ╰─ Certbot cron/renew
           └─ Cloud DNS A-record  ──► Static IP of VM
```

---

## 3. One-time Google Cloud tasks

| Task                                                      | Command / UI                                                    | Doc                               |
| --------------------------------------------------------- | --------------------------------------------------------------- | --------------------------------- |
| **Reserve a static IP** (so reboots never break DNS)      | Console ▶ VPC Network ▶ External IPs ▶ “Reserve static address” | ([Google Cloud Documentation][2]) |
| **Create firewall rules**                                 | ```bash                                                         |                                   |
| gcloud compute firewall-rules create allow-http \         |                                                                 |                                   |
| --direction=INGRESS --priority=1000 --network=default \   |                                                                 |                                   |
| --action=ALLOW --rules=tcp:80 --source-ranges=0.0.0.0/0 \ |                                                                 |                                   |
| --target-tags=http-server                                 |                                                                 |                                   |

gcloud compute firewall-rules create allow-https 
--direction=INGRESS --priority=1000 --network=default 
--action=ALLOW --rules=tcp:443 --source-ranges=0.0.0.0/0 
--target-tags=https-server

````| :contentReference[oaicite:2]{index=2} |
| **Create the VM** | ```bash
gcloud compute instances create n8n-free \
  --zone=us-west1-b \
  --machine-type=e2-micro \
  --image-family=debian-12 --image-project=debian-cloud \
  --boot-disk-size=30GB \
  --tags=http-server,https-server \
  --address=YOUR_STATIC_IP \
  --metadata=startup-script-url=gs://YOUR_BUCKET/n8n-bootstrap.sh
``` | Free-tier spec :contentReference[oaicite:3]{index=3} |

*(If you don’t want to host the script in Cloud Storage, you can paste it directly with `--metadata startup-script='...'`)*  

---

## 4. The **`n8n-bootstrap.sh`** startup script  

Save the snippet below, upload it to a GCS bucket, or run it manually after SSH’ing in.  
It:

1. Adds **2 GB swap** (prevents OOM on 0.6 vCPU/2 GB RAM) :contentReference[oaicite:4]{index=4}  
2. Installs **Docker Engine** the official way :contentReference[oaicite:5]{index=5}  
3. Installs **Nginx**  
4. Drops a **Docker Compose** file for n8n with recommended env-vars :contentReference[oaicite:6]{index=6}  
5. Creates a **systemd unit** so n8n auto-starts  
6. Pre-configures the Nginx vhost (HTTP only—Certbot runs later)

```bash
#!/usr/bin/env bash
set -euxo pipefail
DOMAIN_NAME="vanessa.pimpshizzle.com"   # <<< change me

## 1. Swap (2 GB)
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

## 2. OS update & deps
apt-get update && apt-get upgrade -y
apt-get install -y ca-certificates curl gnupg lsb-release nginx

## 3. Docker CE
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
usermod -aG docker $SUDO_USER

## 4. n8n compose stack
mkdir -p /opt/n8n/{data,settings}
cat >/opt/n8n/docker-compose.yml <<EOF
version: "3.8"
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      N8N_PROTOCOL=https
      N8N_HOST=$DOMAIN_NAME
      WEBHOOK_URL=https://$DOMAIN_NAME/
      DB_SQLITE_POOL_SIZE=2
      N8N_RUNNERS_ENABLED=true
    volumes:
      - ./data:/home/node/.n8n
      - ./settings:/data/settings
EOF

## 5. systemd wrapper
cat >/etc/systemd/system/n8n-compose.service <<'EOF'
[Unit]
Description=n8n via docker compose
Requires=docker.service
After=docker.service
[Service]
Type=oneshot
WorkingDirectory=/opt/n8n
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now n8n-compose

## 6. Nginx reverse proxy (HTTP)
cat >/etc/nginx/sites-available/n8n <<EOF
server {
  listen 80;
  server_name $DOMAIN_NAME;
  location / {
    proxy_pass http://localhost:5678;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_buffering off;
  }
}
EOF
ln -s /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

echo ">> Bootstrap done. Point DNS A record to this VM, then run certbot:"
echo "   sudo apt install -y certbot python3-certbot-nginx"
echo "   sudo certbot --nginx -d $DOMAIN_NAME"
````

---

## 5. DNS & TLS

1. **Add an `A` record** in your registrar for `vanessa.pimpshizzle.com → 34.121.110.233` (your static IP).
   Wait for it to propagate (TTL 600 s).
2. SSH in and issue the certificate:

```bash
sudo apt install -y certbot python3-certbot-nginx   # one-shot installer :contentReference[oaicite:7]{index=7}
sudo certbot --nginx -d vanessa.pimpshizzle.com
```

Certbot drops an auto-renew cron + systemd timer, so renewal is automatic.

---

## 6. Operating the stack

| Task                     | Command                                                                     |
| ------------------------ | --------------------------------------------------------------------------- |
| View logs                | `docker logs -f n8n`                                                        |
| Update container version | `docker pull docker.n8n.io/n8nio/n8n && docker compose restart`             |
| OS patching              | `sudo apt update && sudo apt upgrade -y` (swap prevents kernel-upgrade OOM) |
| Free up space            | `docker system prune -af && journalctl --vacuum-time=14d`                   |

---

## 7. Optional hardening & upgrades

* **Auto-snapshots** – schedule weekly PD snapshots from the console (first 5 GB/month are free).
* **Fail2ban** for SSH & Nginx logs if you expose admin login.
* **Move SQLite to Cloud SQL** if workflows or executions exceed micro instance disk IOPS.
* **Switch to Container-Optimized OS** once configuration stabilises—smaller attack surface, auto-patched kernel (but no apt). ([Google Cloud Documentation][1])

---

## 8. Quick validation checklist

* `curl -IL https://vanessa.pimpshizzle.com` returns `HTTP/2 200`
* `docker ps` shows `n8n` **Up**
* `systemctl status n8n-compose` is **active (exited)**
* `free -h` shows **Swap: 2.0G**

If all true, you now have a **hands-free, reboot-proof, HTTPS-secured n8n** that fits entirely inside Google’s perpetual free tier. 🎉

---

### References

Free-tier limits ([Google Cloud Documentation][3]) | Docker on Debian ([Docker Documentation][4]) | Swap example ([BadlyWired.com][5]) | n8n env-vars ([n8n Docs][6]) | Docker-Compose guide ([n8n Docs][7]) | Certbot on Debian ([certbot.eff.org][8]) | Static IP reservation ([Google Cloud Documentation][2]) | Firewall rule sample ([Google Cloud Documentation][9]) | Container-Optimized OS overview ([Google Cloud Documentation][1]) | VPC firewall concepts ([Google Cloud Documentation][10])

[1]: https://docs.cloud.google.com/container-optimized-os/docs/concepts/features-and-benefits?utm_source=chatgpt.com "Container-Optimized OS Overview"
[2]: https://docs.cloud.google.com/vpc/docs/reserve-static-external-ip-address?utm_source=chatgpt.com "Reserve a static external IP address | Virtual Private Cloud"
[3]: https://docs.cloud.google.com/free/docs/compute-getting-started?utm_source=chatgpt.com "Get started with Compute Engine free features and trial offers"
[4]: https://docs.docker.com/engine/install/debian/?utm_source=chatgpt.com "Install Docker Engine on Debian"
[5]: https://badlywired.com/2016/08/adding-swap-google-compute-engine/?utm_source=chatgpt.com "Adding Swap to Google Compute Engine | BadlyWired.com"
[6]: https://docs.n8n.io/hosting/configuration/configuration-examples/webhook-url/?utm_source=chatgpt.com "Configure webhook URLs with reverse proxy | n8n Docs"
[7]: https://docs.n8n.io/hosting/installation/server-setups/docker-compose/?utm_source=chatgpt.com "Docker Compose | n8n Docs"
[8]: https://certbot.eff.org/instructions?os=pip&ws=nginx&utm_source=chatgpt.com "Nginx on Linux (pip) - Certbot Instructions | Certbot"
[9]: https://docs.cloud.google.com/migrate/containers/docs/migrate-vm?hl=es-419&utm_source=chatgpt.com "Migra desde una VM de Linux con la CLI de Migrate to ..."
[10]: https://docs.cloud.google.com/firewall/docs/using-firewalls?utm_source=chatgpt.com "Use VPC firewall rules"
