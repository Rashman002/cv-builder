#!/usr/bin/env bash
# Mac only file. deploy-to-vps.sh streams it over SSH and runs it on the VPS.
# It is never saved on the server.
set -euo pipefail
MODE="${1:-}"; DOMAIN="${2:-}"; NEW_USER="${3:-}"; NEW_PASS="${4:-}"
APP_DIR=/var/www/cv-builder
APP_NAME=cv-builder
export DEBIAN_FRONTEND=noninteractive

if [ "$MODE" = prep ]; then
  command -v rsync >/dev/null 2>&1 || { apt-get update -qq; apt-get install -y -qq rsync; }
  if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
  fi
  NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]')
  if [ "$NODE_MAJOR" -lt 18 ]; then echo "Node $NODE_MAJOR found; version 18 or newer is required."; exit 1; fi
  command -v pm2 >/dev/null 2>&1 || npm install -g pm2
  mkdir -p "$APP_DIR/data"
  # Leftovers from the earlier setup (git repo and upload folder)
  rm -rf /var/repo/cv-builder /var/repo/cv-builder.git /tmp/cv-builder-src
  rmdir /var/repo 2>/dev/null || true
  exit 0
fi

[ "$MODE" = finish ] || { echo "Unknown mode: $MODE"; exit 1; }

ENV_FILE="$APP_DIR/.env"
if [ -n "$NEW_USER" ] && [ -n "$NEW_PASS" ]; then
  PORT_KEEP=$(grep -E '^PORT=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 || true)
  printf 'PORT=%s\nAPP_USER=%s\nAPP_PASS=%s\n' "${PORT_KEEP:-3070}" "$NEW_USER" "$NEW_PASS" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi
APP_PORT=$(grep -E '^PORT=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 || true)
APP_PORT=${APP_PORT:-3070}

cd "$APP_DIR"
if pm2 describe "$APP_NAME" >/dev/null 2>&1; then
  pm2 restart "$APP_NAME" --update-env
else
  if ss -ltn | grep -q ":$APP_PORT "; then
    echo "Port $APP_PORT is used by another app. On the VPS run:"
    echo "  echo PORT=3080 >> $ENV_FILE"
    echo "then deploy again."
    exit 1
  fi
  pm2 start ecosystem.config.js
fi
pm2 save >/dev/null
sleep 1
CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$APP_PORT/api/health" || true)
case "$CODE" in 200|401) echo "    App is running on port $APP_PORT";; *) echo "App did not start. Check: pm2 logs $APP_NAME"; exit 1;; esac

CONF="/etc/nginx/sites-available/$DOMAIN"
if [ ! -f "$CONF" ]; then
  echo "==> Creating Nginx site for $DOMAIN"
  cat > "$CONF" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    client_max_body_size 12m;

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX
  ln -sf "$CONF" "/etc/nginx/sites-enabled/$DOMAIN"
  nginx -t && systemctl reload nginx
fi

if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  if command -v certbot >/dev/null 2>&1; then
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --redirect --register-unsafely-without-email \
      || echo "SSL step failed. Check the DNS record for $DOMAIN, then run: certbot --nginx -d $DOMAIN"
  else
    echo "certbot not found. Install it with: apt-get install -y certbot python3-certbot-nginx"
  fi
fi

echo
echo "Done. Open https://$DOMAIN"
echo "On the server: $APP_DIR has only the app files, data/ (saved CVs) and .env if set."
