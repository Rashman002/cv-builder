#!/usr/bin/env bash
# Mac only file. deploy-to-vps.sh sends it over SSH and runs it on the VPS as your
# login user. It is never saved on the server. sudo is used only for system steps.
set -euo pipefail
DOMAIN="${1:-}"; NEW_USER="${2:-}"; NEW_PASS="${3:-}"
APP_DIR=/var/www/cv-builder
APP_NAME=cv-builder
UPLOAD="$HOME/.cv-builder-upload"
ME=$(id -un)
SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"
export DEBIAN_FRONTEND=noninteractive
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
if [ -s "$HOME/.nvm/nvm.sh" ]; then . "$HOME/.nvm/nvm.sh" >/dev/null; fi

[ -f "$UPLOAD/server.js" ] || { echo "Upload not found in $UPLOAD"; exit 1; }
if [ -n "$SUDO" ]; then sudo -v; fi

if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO bash -
  $SUDO apt-get install -y nodejs
fi
NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]')
if [ "$NODE_MAJOR" -lt 18 ]; then echo "Node $NODE_MAJOR found; version 18 or newer is required."; exit 1; fi
command -v pm2 >/dev/null 2>&1 || npm install -g pm2 >/dev/null 2>&1 || $SUDO npm install -g pm2

# If an earlier setup started the app under root's pm2, move it to this user.
if [ -n "$SUDO" ] && sudo bash -lc 'command -v pm2 >/dev/null && pm2 describe cv-builder' >/dev/null 2>&1; then
  sudo bash -lc 'pm2 delete cv-builder >/dev/null && pm2 save >/dev/null'
fi

echo "==> Copying app files to $APP_DIR"
$SUDO mkdir -p "$APP_DIR/data"
$SUDO chown -R "$ME": "$APP_DIR"
rsync -a --delete --exclude '/data/' --exclude '/.env' "$UPLOAD/" "$APP_DIR/"
rm -rf "$UPLOAD"
# Leftovers from the earlier setup (git repo and upload folder)
$SUDO rm -rf /var/repo/cv-builder /var/repo/cv-builder.git /tmp/cv-builder-src
$SUDO rmdir /var/repo 2>/dev/null || true

ENV_FILE="$APP_DIR/.env"
if [ -n "$NEW_USER" ] && [ -n "$NEW_PASS" ]; then
  PORT_KEEP=$(grep -E '^PORT=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 || true)
  printf 'PORT=%s\nAPP_USER=%s\nAPP_PASS=%s\n' "${PORT_KEEP:-3070}" "$NEW_USER" "$NEW_PASS" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi
APP_PORT=$(grep -E '^PORT=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 || true)
APP_PORT=${APP_PORT:-3070}

echo "==> Starting app with pm2"
cd "$APP_DIR"
if pm2 describe "$APP_NAME" >/dev/null 2>&1; then
  pm2 restart "$APP_NAME" --update-env >/dev/null
else
  if ss -ltn | grep -q ":$APP_PORT "; then
    echo "Port $APP_PORT is used by another app. On the VPS run:"
    echo "  echo PORT=3080 >> $ENV_FILE"
    echo "then deploy again."
    exit 1
  fi
  pm2 start ecosystem.config.js >/dev/null
fi
pm2 save >/dev/null
sleep 1
CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$APP_PORT/api/health" || true)
case "$CODE" in 200|401) echo "    App is running on port $APP_PORT";; *) echo "App did not start. Check: pm2 logs $APP_NAME"; exit 1;; esac

CONF="/etc/nginx/sites-available/$DOMAIN"
if [ ! -f "$CONF" ]; then
  echo "==> Creating Nginx site for $DOMAIN"
  $SUDO tee "$CONF" >/dev/null <<NGINX
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
  $SUDO ln -sf "$CONF" "/etc/nginx/sites-enabled/$DOMAIN"
  $SUDO nginx -t && $SUDO systemctl reload nginx
fi

if ! $SUDO test -d "/etc/letsencrypt/live/$DOMAIN"; then
  if command -v certbot >/dev/null 2>&1; then
    $SUDO certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --redirect --register-unsafely-without-email \
      || echo "SSL step failed. Check the DNS record for $DOMAIN, then run: sudo certbot --nginx -d $DOMAIN"
  else
    echo "certbot not found. Install it with: sudo apt-get install -y certbot python3-certbot-nginx"
  fi
fi

echo
echo "Done. Open https://$DOMAIN"
