# Set Up An Ubuntu VPS

Use a fresh Ubuntu VPS with sudo/root access. Keep the provider console available and the original SSH session open through step 7. Stop if any verification fails.

## 1. Prepare An SSH Key — Local

Create a dedicated key if you do not already have one. Set a passphrase; do not overwrite an existing key.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_vps
cat ~/.ssh/id_ed25519_vps.pub
```

Copy the public-key line. Keep the private key on your computer.

## 2. Connect To The VPS — Local

Replace `YOUR_VPS_IP` and use the initial account supplied by the provider:

```bash
ssh root@YOUR_VPS_IP
```

For a non-root initial account, run `sudo -i` on the VPS.

## 3. Download And Configure — VPS

```bash
cd /root
apt-get update
apt-get install -y curl
curl -fsSLO https://raw.githubusercontent.com/pthnhan/vps-setup/main/1st-setup/setup.sh
chmod 700 setup.sh
nano setup.sh
```

Set these values at the top of the file:

```bash
ADMIN_USER="deploy"
SSH_PORT="2222"
SSH_PUBLIC_KEY="PASTE_YOUR_PUBLIC_KEY_HERE"
TIMEZONE="UTC"
SWAP_SIZE_GB="2"
```

| Setting | Value to use |
| --- | --- |
| `ADMIN_USER` | Non-root administrator username |
| `SSH_PORT` | Port from `1024` to `65535` |
| `SSH_PUBLIC_KEY` | Complete `.pub` line from step 1 |
| `TIMEZONE` | `UTC`, `Asia/Ho_Chi_Minh`, or another valid timezone |
| `SWAP_SIZE_GB` | GiB to allocate, or `0` to skip |

Open the chosen TCP port in the **provider firewall**. Keep TCP `22` open.

## 4. Run Setup — VPS

```bash
bash /root/setup.sh
```

Set the administrator's sudo password when prompted. Wait for `Initial setup finished`.

## 5. Verify The Administrator Login — New Local Terminal

Use your chosen key path, port, username, and IP in all following commands:

```bash
ssh -o IdentitiesOnly=yes -o PreferredAuthentications=publickey -o ControlPath=none \
  -i ~/.ssh/id_ed25519_vps -p 2222 deploy@YOUR_VPS_IP
```

Inside this new VPS session:

```bash
sudo -v
docker version
docker compose version
```

## 6. Finalize — New VPS Session

Run directly as the administrator from step 5:

```bash
sudo env SSH_CONNECTION="$SSH_CONNECTION" bash /root/setup.sh --finalize
```

Wait for `First setup complete`.

## 7. Verify And Reboot

**Local:** open another terminal and repeat the login from step 5.

**VPS:** verify sudo:

```bash
sudo -v
```

**Provider dashboard:** remove TCP `22` from the firewall; keep the new SSH port open.

**VPS:** reboot after successful verification:

```bash
sudo reboot
```

**Local:** wait for the VPS to restart, then reconnect with the command from step 5.

**VPS:** verify after reboot:

```bash
sudo -v
docker version
docker compose version
```

## 8. Save The SSH Connection — Local

Open a local terminal, outside the VPS session:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/config
chmod 600 ~/.ssh/config
nano ~/.ssh/config
```

Add or update this block **before any `Host *` defaults**. Replace the four connection values with yours; keep your other host entries.

```sshconfig
Host vps
    HostName YOUR_VPS_IP
    User deploy
    Port 2222
    IdentityFile ~/.ssh/id_ed25519_vps
    IdentitiesOnly yes
    PreferredAuthentications publickey
    AddKeysToAgent yes
```

### macOS: Save The Key Passphrase

Add `UseKeychain yes` inside the same `Host vps` block:

```sshconfig
    UseKeychain yes
```

Load the key with Apple's SSH client, then enter its passphrase once:

```bash
/usr/bin/ssh-add --apple-use-keychain ~/.ssh/id_ed25519_vps
```

Use `/usr/bin/ssh` if another installed SSH client rejects `UseKeychain`.

### Linux: Load The Key Into ssh-agent

Use your desktop's existing agent. If no agent is running, start one:

```bash
if [ -z "${SSH_AUTH_SOCK:-}" ]; then
  eval "$(ssh-agent -s)"
fi
ssh-add ~/.ssh/id_ed25519_vps
```

Enter the passphrase once per agent session; reload the key after a local logout/reboot if needed.

### Connect

```bash
ssh vps
```

Keep the key passphrase enabled and saved in Keychain/agent. Continue entering the VPS account password for `sudo`.

## 9. Install Services — VPS

Inside `ssh vps`:

```bash
git clone https://github.com/pthnhan/vps-setup.git "$HOME/vps-setup"
cd "$HOME/vps-setup"
```

Continue with [database setup](../database/README.md).

## If A Step Fails

Keep a working session open or use the provider console. Run on the VPS:

```bash
sudo sshd -t
sudo ss -ltnp
sudo journalctl -u ssh.service -u ssh.socket -n 50 --no-pager
```

- Login denied: check username, port, and key against step 3.
- Finalize rejected: reconnect as `ADMIN_USER` on `SSH_PORT`, then copy the complete step 6 command.
- Interrupted setup: fix the reported error and rerun `--setup` with the same settings before hardening; use `--finalize` after hardening.
- SSH configuration conflict: inspect `/etc/ssh/sshd_config` and `/etc/ssh/sshd_config.d/`; resolve the reported override before retrying.

[SSH config reference](https://man.openbsd.org/ssh_config) · [ssh-agent key loading](https://man.openbsd.org/ssh-add)
