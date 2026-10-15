#!/usr/bin/env bash
# Mac only. Sends ONLY the vps/ folder to the server and (re)starts the app.
#   First time: ./deploy-to-vps.sh root@VPS_IP cv.lionedge.com.ng [username] [password]
#   After that: ./deploy-to-vps.sh   (or Cmd+Shift+B in VS Code; server and domain are remembered)
set -euo pipefail
cd "$(dirname "$0")"
CONF=.deploy.conf
if [ -f "$CONF" ]; then . "./$CONF"; fi
TARGET="${1:-${TARGET:-}}"; DOMAIN="${2:-${DOMAIN:-}}"; U="${3:-}"; P="${4:-}"
if [ -z "$TARGET" ] || [ -z "$DOMAIN" ]; then
  echo "Usage: ./deploy-to-vps.sh root@VPS_IP cv.lionedge.com.ng [username] [password]"; exit 1
fi
printf 'TARGET=%q\nDOMAIN=%q\n' "$TARGET" "$DOMAIN" > "$CONF"

APP_DIR=/var/www/cv-builder
for f in vps/server.js vps/package.json vps/ecosystem.config.js vps/public/index.html; do
  [ -f "$f" ] || { echo "Missing $f"; exit 1; }
done
if command -v git >/dev/null && [ -n "$(git status --porcelain -- vps 2>/dev/null)" ]; then
  echo "Note: vps/ has uncommitted changes. Deploying them anyway."
fi

SUDO=""; RSYNC_EXTRA=()
if [ "${TARGET%%@*}" != root ]; then SUDO="sudo"; RSYNC_EXTRA=(--rsync-path="sudo rsync"); fi

echo "==> Preparing server ($TARGET)"
ssh "$TARGET" "$SUDO bash -s -- prep" < server-setup.sh

echo "==> Uploading vps/ only (saved CVs and .env on the server are kept)"
rsync -az --delete --exclude '/data/' --exclude '/.env' --exclude '.DS_Store' \
  ${RSYNC_EXTRA[@]+"${RSYNC_EXTRA[@]}"} vps/ "$TARGET:$APP_DIR/"

echo "==> Starting app"
ssh "$TARGET" "$SUDO bash -s -- finish $(printf '%q ' "$DOMAIN" "$U" "$P")" < server-setup.sh
