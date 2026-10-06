# Dice Sorting Game - VM setup

Three machines:

| Machine | Role | Gets |
|---|---|---|
| Server VM (Ubuntu 22.04+, `10.1.21.184`) | Runs the backend API | `dicegame-server.tar.gz` |
| Kali VM | Player | `dicegame-client.tar.gz` |
| Admin Ubuntu VM | Plays as admin | `dicegame-client.tar.gz` |

The clients run the game locally and talk to the server over HTTP on port 8000. If the server's IP is not `10.1.21.184`, substitute yours in every command below.

Every VM needs SSH running to receive files (or use your hypervisor's shared folder instead):

```bash
sudo apt install -y openssh-server && sudo systemctl enable --now ssh
```

On Kali, SSH is already installed; only `sudo systemctl enable --now ssh` is needed.

## 0. Build the bundles (Windows dev machine)

1. In Godot: Project > Export > Linux/X11 > Export Project, with Embed PCK ticked. Re-export after any code change.
2. From the project folder in PowerShell:

```powershell
.\deploy\build-bundles.ps1 -ServerUrl "http://10.1.21.184:8000"
```

This writes `dist/dicegame-server.tar.gz` and `dist/dicegame-client.tar.gz`. It warns if the exported binary is older than your latest code.

## 1. Server VM

Copy the archive over (from the Windows machine):

```bash
scp dist/dicegame-server.tar.gz <user>@10.1.21.184:~/
```

On the server VM, extract and install:

```bash
tar -xzf dicegame-server.tar.gz && cd dicegame-server && sudo bash install.sh
```

The server needs internet during install (apt and pip download packages). `install.sh` installs Python, creates a service user, generates a secret key, starts the `dicegame-backend` service, opens port 8000 if `ufw` is active, and tests the API. It ends by printing the address clients should use. Re-running it upgrades the code and keeps the database and secret key.

Day-to-day commands:

```bash
sudo systemctl status dicegame-backend
```

```bash
journalctl -u dicegame-backend -n 50
```

```bash
sudo systemctl restart dicegame-backend
```

Reset all accounts and saves:

```bash
sudo systemctl stop dicegame-backend && sudo rm /var/lib/dicegame/dicegame.db && sudo systemctl start dicegame-backend
```

The database is `/var/lib/dicegame/dicegame.db`; the app is in `/opt/dicegame`. On first start the server creates the admin account `admin` / `password1`.

## 2. Client VMs (Kali and the admin Ubuntu)

Copy the archive over (from the Windows machine), once per VM:

```bash
scp dist/dicegame-client.tar.gz <user>@<client-vm-ip>:~/
```

On the client VM, extract it:

```bash
tar -xzf dicegame-client.tar.gz && cd dicegame-client
```

Check the server is reachable before launching. This should print JSON containing `"role":"guest"`:

```bash
curl -s -X POST http://10.1.21.184:8000/auth/guest
```

Run the game from a graphical desktop session (it won't start from a bare shell):

```bash
bash run.sh
```

`run.sh` refuses to start while `server_url.txt` still contains the `REPLACE` placeholder. To change the server address later, edit `server_url.txt` (one line, e.g. `http://10.1.21.184:8000`); no re-export is needed.

Logins: players register an account or play as guest. The admin VM logs in as `admin` / `password1`. In game, press `` ` `` for the command console (try `help`; only admin can run commands) and Esc for the pause menu.

## 3. Troubleshooting

| Problem | Check |
|---|---|
| `curl` to the server hangs or fails | VM network mode must be bridged or a shared host-only/internal network, not plain NAT. On the server: `sudo systemctl status dicegame-backend`, `sudo ufw status` (port 8000 must be allowed), `ip -4 addr show` (is the IP what you expect?). |
| Game says it can't reach the server | Same as above; also confirm `server_url.txt` has the right IP and no stray text. |
| Game won't start or is very slow | It needs a graphical session. If the VM has no GPU, enable 3D acceleration in the hypervisor display settings; otherwise it falls back to software rendering. |
| `run.sh` says to edit `server_url.txt` | The bundle was built without `-ServerUrl`. Put the server address in it. |
| Server IP changed | Edit `server_url.txt` on each client. Give the server a static IP or DHCP reservation to avoid this. |
| Install fails on the server | Needs Ubuntu 22.04 or newer and internet access. Read the last error line from `install.sh`. |

## Notes

- Traffic is plain HTTP (no TLS): passwords, tokens and commands are readable by anyone on the same network.
- The default admin password is intentionally weak. Change it or don't expose the server if that isn't what you want.

Command references: `systemctl(1)`, `journalctl(1)`, `scp(1)`, `ufw(8)`, `tar(1)`, Godot docs "Exporting for Linux".
