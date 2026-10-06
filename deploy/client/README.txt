Dice Sorting Game - client bundle

Needs: a graphical desktop session (this is a 3D game, it won't run from a bare shell).
If the VM has no GPU, enable 3D acceleration in the hypervisor's display settings.

1. Extract:  tar -xzf dicegame-client.tar.gz
2. Check server_url.txt contains the server's address, e.g. http://192.168.1.50:8000
   (edit it with any text editor - no re-export needed if the server's IP changes)
3. Run:      cd dicegame-client && bash run.sh

Logins: players register an account or play as guest. The admin account is admin / password1.
