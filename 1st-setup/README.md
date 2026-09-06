# First Setup For A New Ubuntu VPS

Use `setup.sh` after buying a new Ubuntu VPS. You only need its IP address, the initial login supplied by the provider, and an SSH public key.

The script intentionally uses two runs. The first run prepares the server while keeping port `22` available. The second run disables root/password SSH login and closes port `22`, but only after you have successfully connected through the new port.

## 1. Prepare A Public Key On Your Computer

Use a dedicated key for the VPS when possible. Create one if needed:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_vps
cat ~/.ssh/id_ed25519_vps.pub
```

Copy the complete line printed by the second command. Never copy the private file `~/.ssh/id_ed25519_vps` to the VPS.

## 2. Log In To The New VPS

Use the IP address and initial username supplied by the provider. Most providers use `root`:

```bash
ssh root@YOUR_VPS_IP
```

If the provider uses another initial user, log in with that user and run `sudo -i` before continuing. Keep this session open until setup is complete, and keep the provider's web or serial console available for recovery.

## 3. Download And Edit The Script

Run on the VPS. This downloads one file; it does not clone the repository:

```bash
cd /root
apt-get update
apt-get install -y curl
curl -fsSLO https://raw.githubusercontent.com/pthnhan/vps-setup/main/1st-setup/setup.sh
chmod 700 setup.sh
nano setup.sh
```

Edit the variables at the top:

```bash
ADMIN_USER="deploy"
SSH_PORT="2222"
SSH_PUBLIC_KEY="PASTE_YOUR_PUBLIC_KEY_HERE"
TIMEZONE="UTC"
SWAP_SIZE_GB="2"
```

- `ADMIN_USER`: the non-root administrator the script will create.
- `SSH_PORT`: the new SSH port, from `1024` to `65535`.
- `SSH_PUBLIC_KEY`: the complete public-key line copied in step 1. This is key content, not a filename.
- `TIMEZONE`: a timezone such as `UTC` or `Asia/Ho_Chi_Minh`.
- `SWAP_SIZE_GB`: swap size in GiB; use `0` to skip swap creation.

Before running the script, allow the chosen `SSH_PORT` in the VPS provider's firewall or security group. Keep port `22` open.

## 4. Run Initial Setup

```bash
bash /root/setup.sh
```

The script validates its variables, then:

1. Updates Ubuntu and installs base command-line packages.
2. Creates `ADMIN_USER`, adds it to `sudo`, and asks for its sudo password.
3. Installs `SSH_PUBLIC_KEY` for that user with the correct permissions.
4. Configures SSH and UFW to accept both port `22` and `SSH_PORT`.
5. Configures Fail2ban, automatic security updates, timezone, and swap.
6. Installs Docker Engine, Buildx, and Docker Compose from Docker's official repository.

The script does not reboot the VPS or close port `22` during this run.

## 5. Verify The New Login

Keep the original session open. From a new terminal on your computer, use the private key paired with `SSH_PUBLIC_KEY`:

```bash
ssh -i ~/.ssh/id_ed25519_vps -p 2222 deploy@YOUR_VPS_IP
```

Replace the key path, port, username, and IP with the values you chose. Inside the new session, verify:

```bash
sudo -v
docker version
docker compose version
```

Do not continue if any command fails. Check the original session or provider console for errors.

## 6. Finalize SSH

Run the command printed by the first setup run. When the script is stored at the path used above, it is:

```bash
sudo bash /root/setup.sh --finalize
```

The script refuses to finalize unless the current SSH session is connected through `SSH_PORT`. It then:

- disables root SSH login;
- disables password and keyboard-interactive SSH authentication;
- leaves only `SSH_PORT` active;
- removes the UFW rule for port `22`;
- updates Fail2ban to monitor only the new port.

After finalization, open one more terminal and verify the new login again. Then remove port `22` from the provider firewall.

If Ubuntu reports that a reboot is required, reboot only after finalization and successful login verification:

```bash
sudo reboot
```

The initial VPS setup is complete. Return to the [repository README](../README.md#after-first-setup) when you are ready to install service modules.

## What The Script Cannot Configure

The script cannot change the VPS provider's external firewall. You must open the new SSH port before the first run and remove port `22` after finalization.

Docker-published ports can bypass UFW. Keep private databases and administration UIs bound to `127.0.0.1` or accessible only through a Docker network.

## References

- [Ubuntu user management](https://ubuntu.com/server/docs/how-to/security/user-management/)
- [Ubuntu OpenSSH server](https://ubuntu.com/server/docs/how-to/security/openssh-server/)
- [Ubuntu firewall](https://ubuntu.com/server/docs/how-to/security/firewalls/)
- [Ubuntu automatic security updates](https://documentation.ubuntu.com/security/security-updates/)
- [Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Docker Linux post-installation](https://docs.docker.com/engine/install/linux-postinstall/)
- [Docker firewall considerations](https://docs.docker.com/engine/network/packet-filtering-firewalls/)
