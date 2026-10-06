#!/bin/bash
set -eu
cd "$(dirname "${BASH_SOURCE[0]}")"

if grep -q REPLACE server_url.txt; then
  echo "Edit server_url.txt and put the server's address in it, e.g. http://192.168.1.50:8000"
  exit 1
fi

BIN="./Dice Sorting Game.x86_64"
chmod +x "$BIN"
exec "$BIN" "$@"
