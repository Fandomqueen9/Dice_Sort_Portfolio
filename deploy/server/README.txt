Dice Sorting Game - server bundle

Needs: Ubuntu 22.04 or newer, internet access (apt and pip download packages).

1. Extract:   tar -xzf dicegame-server.tar.gz
2. Install:   cd dicegame-server && sudo bash install.sh
3. At the end it prints the address to give the clients (http://<this-machine's-ip>:8000).
   Give this machine a static IP or DHCP reservation so that address doesn't change.

Re-running install.sh upgrades the code and keeps the database and secret key.

Default admin account: admin / password1 (created on first start).

Logs:    journalctl -u dicegame-backend -n 50
Restart: sudo systemctl restart dicegame-backend
Reset all accounts and saves: sudo systemctl stop dicegame-backend && sudo rm /var/lib/dicegame/dicegame.db && sudo systemctl start dicegame-backend
