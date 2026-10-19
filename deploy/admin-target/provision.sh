#!/bin/bash
set -euo pipefail

# This script configures the admin target VM with SSH access, flag, and SUID binary.
# It MUST run as root and REQUIRES deploy_key.pub in the same directory.

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (sudo)."
    exit 1
fi

# Install dependencies
apt-get update
apt-get install -y openssh-server gcc

# Create deploy user if not exists
if ! id "deploy" &>/dev/null; then
    useradd --create-home --shell /bin/bash deploy
    echo "Created deploy user."
fi

# Check for deploy_key.pub and set up SSH
if [ ! -f "deploy_key.pub" ]; then
    echo "Error: deploy_key.pub not found in current directory."
    echo "Run: scp /opt/dicegame/.deploy/id_ed25519.pub ./deploy_key.pub"
    exit 1
fi

mkdir -p /home/deploy/.ssh
if ! grep -q "$(cat deploy_key.pub)" /home/deploy/.ssh/authorized_keys 2>/dev/null; then
    cat deploy_key.pub >> /home/deploy/.ssh/authorized_keys
fi
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh

# Enable SSH
systemctl enable --now ssh

# Create randomized flag if not exists
if [ ! -f "/root/flag.txt" ]; then
    FLAG_SUFFIX=$(openssl rand -hex 8)
    echo "FLAG{netcheck_to_root_${FLAG_SUFFIX}}" > /root/flag.txt
    chmod 600 /root/flag.txt
    chown root:root /root/flag.txt
    echo "Flag created: $(cat /root/flag.txt)"
fi

# Compile and install flagread with SUID bit
if [ ! -f "flagread.c" ]; then
    echo "Error: flagread.c not found in current directory."
    exit 1
fi

gcc -O2 -o /usr/local/bin/flagread flagread.c
chown root:root /usr/local/bin/flagread
chmod 4755 /usr/local/bin/flagread

echo ""
echo "=== Admin VM provisioning complete ==="
echo "deploy user: $(id deploy)"
echo "flagread binary: $(ls -l /usr/local/bin/flagread)"
echo "flag file: $(ls -l /root/flag.txt)"
echo "SSH service: $(systemctl is-active ssh)"