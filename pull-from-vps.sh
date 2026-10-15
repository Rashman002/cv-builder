#!/usr/bin/env bash
# Mac only. Copies the 4 app files from the VPS into vps/. Never pulls CVs or .env.
set -euo pipefail
cd "$(dirname "$0")"
if [ -f .deploy.conf ]; then . ./.deploy.conf; fi
TARGET="${1:-${TARGET:-}}"
[ -n "$TARGET" ] || { echo "Usage: ./pull-from-vps.sh root@VPS_IP  (or deploy once first)"; exit 1; }
APP_DIR=/var/www/cv-builder
mkdir -p vps/public
rsync -az "$TARGET:$APP_DIR/server.js" "$TARGET:$APP_DIR/package.json" "$TARGET:$APP_DIR/ecosystem.config.js" vps/
rsync -az "$TARGET:$APP_DIR/public/index.html" vps/public/
echo "Pulled into vps/. Review with: git diff"
