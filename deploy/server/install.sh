#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo: sudo bash install.sh"
  exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR=/opt/dicegame
DATA_DIR=/var/lib/dicegame
UNIT=/etc/systemd/system/dicegame-backend.service

apt-get update
apt-get install -y python3 python3-venv curl nmap openssh-client


python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' \
  || { echo "Python 3.10+ is required (Ubuntu 22.04 or newer)."; exit 1; }

id dicegame >/dev/null 2>&1 || useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin dicegame

# SSH key for dicegame user — used in CTF chain; deliberately readable by dicegame account
DEPLOY_DIR="/opt/dicegame/.deploy"
KEY="$DEPLOY_DIR/id_ed25519"
if [ ! -f "$KEY" ]; then
  mkdir -p "$DEPLOY_DIR"
  ssh-keygen -t ed25519 -N "" -C "dicegame-deploy-key (lab only)" -f "$KEY"
  chown -R dicegame:dicegame "$DEPLOY_DIR"
  chmod 700 "$DEPLOY_DIR"
  chmod 600 "$KEY" "$KEY.pub"
  echo "SSH key generated for dicegame user."
fi

mkdir -p "$APP_DIR" "$DATA_DIR"
rm -rf "$APP_DIR/backend"
cp -r "$HERE/backend" "$APP_DIR/backend"
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --quiet -r "$APP_DIR/backend/requirements.txt"
chown -R dicegame:dicegame "$DATA_DIR"

# Keep the existing secret on re-runs so issued tokens stay valid.
if [ -f "$UNIT" ] && grep -q '^Environment=SECRET_KEY=' "$UNIT"; then
  SECRET_KEY="$(grep '^Environment=SECRET_KEY=' "$UNIT" | head -1 | cut -d= -f3-)"
else
  SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
fi
sed "s|change-me-to-a-real-secret|$SECRET_KEY|" "$HERE/dicegame-backend.service" > "$UNIT"

systemctl daemon-reload
systemctl enable dicegame-backend
systemctl restart dicegame-backend

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow 8000/tcp
fi

sleep 2
if curl -fsS -X POST http://127.0.0.1:8000/auth/guest >/dev/null; then
  echo "Server is up. Put this in each client's server_url.txt: http://$(hostname -I | awk '{print $1}'):8000"
else
  echo "Server did not respond. Check: journalctl -u dicegame-backend -n 50"
  exit 1
fi
