# CV Builder

Only `vps/` goes to the server. Everything else stays on the Mac.

```
vps/                    server.js, package.json, ecosystem.config.js, public/index.html
deploy-to-vps.sh        Mac: upload vps/ and restart the app
pull-from-vps.sh        Mac: copy the 4 app files back from the VPS
server-setup.sh         Mac: streamed over SSH by deploy, never saved on the VPS
start-mac.command       Mac: run locally at http://localhost:3070
```

## Deploy
Double-click **Deploy to VPS.command** (or Cmd+Shift+B in VS Code).
The first time it asks for your VPS login and domain; after that it just deploys.

On the VPS, `/var/www/cv-builder` holds only the app files, `data/` (saved CVs) and `.env` (only if a password or port is set).
Each deploy removes anything else there, plus the old `/var/repo/cv-builder*` and `/tmp/cv-builder-src`.

## Pull from VPS
Terminal > Run Task > Pull from VPS. Copies the 4 app files only, never CVs or `.env`.

## Local data
`vps/data/` (your CVs) and `vps/.env` are git-ignored and never uploaded.
