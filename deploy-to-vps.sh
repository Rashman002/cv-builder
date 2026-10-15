#!/usr/bin/env bash
# Mac only. Sends ONLY the vps/ folder to the server and (re)starts the app.
#   Double-click "Deploy to VPS.command" (or Cmd+Shift+B in VS Code).
#   First run asks for the VPS IP and domain once, then remembers them.
#   Optional password protection: ./deploy-to-vps.sh root@IP domain USERNAME PASSWORD
set -euo pipefail
cd "$(dirname "$0")"
CONF=.deploy.conf
if [ -f "$CONF" ]; then . "./$CONF"; fi
TARGET="${1:-${TARGET:-}}"; DOMAIN="${2:-${DOMAIN:-}}"; U="${3:-}"; P="${4:-}"
if [ -z "$TARGET" ]; then
  read -r -p "VPS IP address: " IP
  [ -n "$IP" ] || { echo "No IP given."; exit 1; }
  case "$IP" in *@*) TARGET="$IP";; *) TARGET="root@$IP";; esac
fi
if [ -z "$DOMAIN" ]; then
  read -r -p "Domain [cv.lionedge.com.ng]: " DOMAIN
  DOMAIN=${DOMAIN:-cv.lionedge.com.ng}
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
