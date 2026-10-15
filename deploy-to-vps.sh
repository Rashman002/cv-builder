#!/usr/bin/env bash
# Mac only. Sends ONLY the vps/ folder to the server and (re)starts the app.
#   Double-click "Deploy to VPS.command" (or Cmd+Shift+B in VS Code).
#   First run asks for the VPS login and domain once, then remembers them.
#   Optional password protection: ./deploy-to-vps.sh user@IP domain USERNAME PASSWORD
set -euo pipefail
cd "$(dirname "$0")"
CONF=.deploy.conf
if [ -f "$CONF" ]; then . "./$CONF"; fi
TARGET="${1:-${TARGET:-}}"; DOMAIN="${2:-${DOMAIN:-}}"; U="${3:-}"; P="${4:-}"
if [ -z "$TARGET" ]; then
  read -r -p "VPS login (e.g. administrator@1.2.3.4): " TARGET
  [ -n "$TARGET" ] || { echo "No login given."; exit 1; }
fi
if [ -z "$DOMAIN" ]; then
  read -r -p "Domain [cv.lionedge.com.ng]: " DOMAIN
  DOMAIN=${DOMAIN:-cv.lionedge.com.ng}
fi
printf 'TARGET=%q\nDOMAIN=%q\n' "$TARGET" "$DOMAIN" > "$CONF"

for f in vps/server.js vps/package.json vps/ecosystem.config.js vps/public/index.html; do
  [ -f "$f" ] || { echo "Missing $f"; exit 1; }
done

# One shared SSH connection, so the VPS password is asked only once.
SSH_OPTS="-o ControlMaster=auto -o ControlPath=/tmp/cvb-ssh-%C -o ControlPersist=120"
cleanup() { ssh $SSH_OPTS -O exit "$TARGET" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "==> Connecting to $TARGET"
ssh $SSH_OPTS -fN "$TARGET"

echo "==> Uploading vps/"
rsync -az --delete --exclude '/data/' --exclude '/.env' --exclude '.DS_Store' \
  -e "ssh $SSH_OPTS" vps/ "$TARGET:.cv-builder-upload/"

echo "==> Installing on the server (enter your VPS password if sudo asks)"
B64=$(base64 < server-setup.sh | tr -d '\n')
ssh $SSH_OPTS -t "$TARGET" "bash -c \"\$(echo $B64 | base64 -d)\" server-setup $(printf '%q ' "$DOMAIN" "$U" "$P")"
