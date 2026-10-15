#!/bin/bash
# Double-click to deploy. First time it asks for your VPS IP and domain.
cd "$(dirname "$0")"
./deploy-to-vps.sh
echo; read -n1 -r -p "Press any key to close..."
