Admin Target VM Provisioning
=============================

This bundle sets up the admin target VM for the CTF challenge.
It creates a low-privilege user and intentional security vulnerabilities
to be exploited via the attack chain.

FILES:
  - provision.sh    : Main provisioning script (run as root with sudo)
  - flagread.c      : Source for SUID binary that reads /root/flag.txt
  - deploy_key.pub  : SSH public key (must be copied from game server)
  - README.txt      : This file

PREREQUISITE:
Before running provision.sh, you MUST copy the SSH public key from the game
server VM into this directory as deploy_key.pub:

  scp user@<server-ip>:/opt/dicegame/.deploy/id_ed25519.pub ./deploy_key.pub

If deploy_key.pub is missing, provision.sh will exit with an error.

USAGE:
  1. Extract this bundle on the admin target VM
  2. Copy deploy_key.pub from the game server (see above)
  3. Run: sudo bash provision.sh
  4. The script will:
     - Install openssh-server and gcc
     - Create the 'deploy' user with the SSH key
     - Generate a randomized flag in /root/flag.txt
     - Compile flagread as a SUID root binary

WARNINGS:
  * This creates intentional SUID escalation vulnerability (CWE-250)
  * The SSH key allows lateral movement from the game server
  * Only run this on a disposable lab VM with no real data
  * Never expose this VM to the internet or untrusted networks
  * Not suitable for production use