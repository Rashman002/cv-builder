#!/bin/bash
# Double-click to run CV Builder on your Mac. Close this window to stop it.
cd "$(dirname "$0")/vps"
for p in /opt/homebrew/bin /usr/local/bin; do [ -x "$p/node" ] && export PATH="$p:$PATH"; done
if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is not installed. Install it with:  brew install node"
  read -n1 -r -p "Press any key to close..."; exit 1
fi
PORT=$(grep -E '^PORT=' .env 2>/dev/null | cut -d= -f2)
export PORT=${PORT:-3070}
(sleep 1; open "http://localhost:$PORT") &
node server.js
