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
ssh -o IdentitiesOnly=yes -o PreferredAuthentications=publickey -o ControlPath=none \
  -i ~/.ssh/id_ed25519_vps -p 2222 deploy@YOUR_VPS_IP
```

Replace the key path, port, username, and IP with the values you chose. These options require a fresh public-key login, so a password fallback or reused connection cannot hide a broken key. A private-key passphrase prompt is normal. Inside the new session, verify:

```bash
sudo -v
docker version
docker compose version
```

Do not continue if any command fails. Check the original session or provider console for errors.

## 6. Finalize SSH

Run the command printed by the first setup run. When the script is stored at the path used above, it is:

```bash
sudo env SSH_CONNECTION="$SSH_CONNECTION" bash /root/setup.sh --finalize
```

`sudo` normally removes `SSH_CONNECTION` from its environment. The `env` argument above passes only that variable from your current shell to the root process. Run it directly from the new administrator login, before entering `sudo -i`, `su`, or a reused tmux/screen session.

The script refuses to finalize if the variable is missing/malformed, its port differs from `SSH_PORT`, or the sudo caller differs from `ADMIN_USER`. This is an accidental-lockout check; a root-capable administrator can override environment variables. It then:

- disables root SSH login;
- disables password and keyboard-interactive SSH authentication;
- leaves only `SSH_PORT` active;
- removes the UFW rule for port `22`;
- updates Fail2ban to monitor only the new port.

The script checks the effective SSH configuration (including `Match` rules for the administrator and root from your current client address) and listening ports. It expects authentication methods `any` or `publickey`; custom MFA policies need a separate setup workflow. If applying SSH fails, it restores the configuration from immediately before that attempt and tries to restart SSH. Keep the original session and provider console available even with this recovery.

After finalization, open one more terminal and repeat the public-key login from step 5 and `sudo -v`. Then remove port `22` from the provider firewall.

If Ubuntu reports that a reboot is required, reboot only after finalization and successful login verification:

```bash
sudo reboot
```

Reconnect after reboot and repeat `sudo -v`, `docker version`, and `docker compose version`.

The initial VPS setup is complete. Return to the [repository README](../README.md#after-first-setup) when you are ready to install service modules.

## Troubleshooting And Reruns

**Already hit “Run finalize from an SSH session connected to the new port” with an older script?** The same `sudo env SSH_CONNECTION="$SSH_CONNECTION" bash /root/setup.sh --finalize` command above works with that script too. You do not need to reinstall Ubuntu or rerun initial setup. First repeat step 5 with the public-key-only options.

To confirm the environment issue without changing anything:

```bash
printf 'Before sudo: %s\n' "$SSH_CONNECTION"
sudo printenv SSH_CONNECTION
```

If the first command shows four fields ending in your new port and the second prints nothing, sudo removed the variable. Do not type a fabricated connection value; pass the actual shell variable.

**Other SSH configuration conflicts:** use the still-open session or provider console:

```bash
sudo sshd -t
sudo sshd -T
sudo ss -ltnp
sudo systemctl status ssh.service ssh.socket --no-pager
sudo journalctl -u ssh.service -u ssh.socket -n 50 --no-pager
sudo grep -RnsE '^[[:space:]]*(Include|Port|ListenAddress|Match|AllowUsers|DenyUsers|AllowGroups|DenyGroups|AuthenticationMethods|PermitRootLogin|PasswordAuthentication|KbdInteractiveAuthentication)' /etc/ssh/sshd_config /etc/ssh/sshd_config.d
```

An additional `Port 22` or an override before the toolkit drop-in can prevent finalization. Review the conflicting provider configuration rather than deleting files blindly. The script leaves the UFW fallback rule in place when SSH validation fails.

**Interrupted setup:** fix the reported error, keep the same edited variables, and rerun `--setup` before finalization. After SSH has been hardened, use `--finalize` to retry remaining checks; the script refuses `--setup` to avoid reopening password/root access and port 22. Do not replace your edited `/root/setup.sh` with a fresh download without preserving its settings.

**Swap:** use `SWAP_SIZE_GB=0` to skip allocation. Existing active swap is left alone. If an interrupted allocation left an unusable `/swapfile`, inspect it before removing or recreating it.

## What The Script Cannot Configure

The script cannot change the VPS provider's external firewall. You must open the new SSH port before the first run and remove port `22` after finalization.

Membership in the Docker group grants root-level control of the VPS; give it only to trusted administrators.

Docker-published ports can bypass UFW. Keep private databases and administration UIs bound to `127.0.0.1` or accessible only through a Docker network.

## References

- [Sudo environment handling](https://github.com/sudo-project/sudo/blob/main/docs/TROUBLESHOOTING.md)

- [Ubuntu user management](https://ubuntu.com/server/docs/how-to/security/user-management/)
- [Ubuntu OpenSSH server](https://ubuntu.com/server/docs/how-to/security/openssh-server/)
- [Ubuntu firewall](https://ubuntu.com/server/docs/how-to/security/firewalls/)
- [Ubuntu automatic security updates](https://documentation.ubuntu.com/security/security-updates/)
- [Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Docker Linux post-installation](https://docs.docker.com/engine/install/linux-postinstall/)
- [Docker firewall considerations](https://docs.docker.com/engine/network/packet-filtering-firewalls/)
