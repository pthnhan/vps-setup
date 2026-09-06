# First Setup For A New Ubuntu VPS

This guide starts with a completely new Ubuntu LTS VPS and ends with a non-root administrative user, SSH key authentication on a custom port, a firewall, Fail2ban, automatic security updates, swap, and Docker Engine with Compose.

Read the whole step you are on before running its commands. Keep the provider's web or serial console available and keep the original SSH session open until the replacement login has been tested.

The examples use:

- VPS address: `YOUR_VPS_IP`
- Initial user: `root`
- Administrative user: `deploy`
- SSH key: `~/.ssh/id_ed25519`
- New SSH port: `2222`

Replace these values consistently when yours differ. Commands labelled **local computer** run on your own machine. Commands labelled **VPS** run on the server.

## 1. Create An SSH Key On Your Local Computer

Check whether the key already exists:

```bash
ls -l ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub
```

If both files exist, keep them and continue. If they do not exist, create them on your local computer:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
```

Use a passphrase when practical. The private file `~/.ssh/id_ed25519` stays on your computer and must never be uploaded or shared. Display the public key that may be copied to the VPS:

```bash
cat ~/.ssh/id_ed25519.pub
ssh-keygen -lf ~/.ssh/id_ed25519.pub
```

The public key is the single line beginning with `ssh-ed25519`. Add it to the VPS provider's SSH-key field when creating the server.

## 2. Create The VPS And Verify Initial Key Login

Create a VPS with a current Ubuntu LTS image. In the provider control panel:

1. Add the public key from step 1.
2. Allow inbound TCP port `22` temporarily.
3. Enable or confirm access to the provider's web or serial console.
4. Record the public IP address.

From your local computer, log in using the exact private key paired with the public key you uploaded:

```bash
ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes root@YOUR_VPS_IP
```

On the first connection, SSH asks whether to trust the server host key. Before accepting it, use the provider console to compare the displayed fingerprint with:

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

### If `/root/.ssh/authorized_keys` Is Missing Or Empty

An empty file means the provider did not install your public key. Open the provider's web or serial console, log in as `root`, then run on the VPS:

```bash
install -d -m 700 /root/.ssh
nano /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
```

Paste the complete public-key line shown by `cat ~/.ssh/id_ed25519.pub` on your local computer, save the file, and test again from a new local terminal:

```bash
ssh -i ~/.ssh/id_ed25519 \
  -o IdentitiesOnly=yes \
  -o PreferredAuthentications=publickey \
  -o PasswordAuthentication=no \
  root@YOUR_VPS_IP
```

Do not continue until this public-key-only login succeeds. Confirm on the VPS that the key file is non-empty:

```bash
wc -l /root/.ssh/authorized_keys
```

The result must be at least `1`.

## 3. Update The VPS

Run as `root` on the VPS:

```bash
apt update
apt upgrade -y
apt install -y sudo nano ca-certificates curl git gnupg htop unzip ufw fail2ban unattended-upgrades zsh build-essential
```

Check whether Ubuntu requests a reboot:

```bash
test -f /var/run/reboot-required && cat /var/run/reboot-required
```

If it prints a message, reboot and reconnect with the key before continuing:

```bash
reboot
```

## 4. Create The Administrative User

Run as `root` on the VPS. Replace `deploy` everywhere if you want another username:

```bash
adduser deploy
usermod -aG sudo deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
install -m 600 -o deploy -g deploy \
  /root/.ssh/authorized_keys \
  /home/deploy/.ssh/authorized_keys
```

The final `install` command copies the verified root key file and sets mode `600`, owner `deploy`, and group `deploy` in one operation. It is safe here because step 2 required `/root/.ssh/authorized_keys` to contain your public key.

Keep the root session open. From a second local terminal, test the new user with key authentication only:

```bash
ssh -i ~/.ssh/id_ed25519 \
  -o IdentitiesOnly=yes \
  -o PreferredAuthentications=publickey \
  -o PasswordAuthentication=no \
  deploy@YOUR_VPS_IP
```

Inside that new VPS session, verify administrative access:

```bash
sudo -v
whoami
```

Continue as `deploy` only after key login and `sudo` both work. Keep the root session open until the SSH port change is finished.

## 5. Change The SSH Port And Harden SSH

Changing the port reduces automated log noise; SSH keys and disabled password login provide the real authentication protection.

First allow TCP `2222` in the provider firewall while keeping port `22` open. Then run as `deploy` on the VPS:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'temporary SSH fallback'
sudo ufw limit 2222/tcp comment 'SSH'
sudo ufw logging low
sudo ufw enable
sudo ufw status verbose
```

Create the SSH configuration directly on the VPS:

```bash
sudo install -d -m 755 /etc/ssh/sshd_config.d
sudo tee /etc/ssh/sshd_config.d/00-hardening.conf > /dev/null <<'EOF'
Port 22
Port 2222
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowUsers deploy
EOF
sudo chmod 600 /etc/ssh/sshd_config.d/00-hardening.conf
```

List every user who needs SSH access on the `AllowUsers` line. Validate the complete configuration before applying it:

```bash
sudo sshd -t
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|allowusers) '
```

Stop if `sshd -t` prints an error or the effective settings differ from the file. Apply the validated configuration according to the active SSH unit:

```bash
if systemctl is-active --quiet ssh.socket; then
  sudo systemctl daemon-reload
  sudo systemctl restart ssh.socket
else
  sudo systemctl restart ssh.service
fi
sudo ss -ltnp | grep -E ':(22|2222)[[:space:]]'
```

Both ports must be listening. From a new local terminal, test the new port:

```bash
ssh -i ~/.ssh/id_ed25519 \
  -o IdentitiesOnly=yes \
  -o PreferredAuthentications=publickey \
  -o PasswordAuthentication=no \
  -p 2222 deploy@YOUR_VPS_IP
```

Inside the new session, run `sudo -v`. Only after that succeeds, edit the SSH file and remove the `Port 22` line:

```bash
sudo nano /etc/ssh/sshd_config.d/00-hardening.conf
sudo sshd -t
if systemctl is-active --quiet ssh.socket; then
  sudo systemctl daemon-reload
  sudo systemctl restart ssh.socket
else
  sudo systemctl restart ssh.service
fi
sudo ss -ltnp | grep -E ':(22|2222)[[:space:]]'
```

Test another fresh login on port `2222`. When port `22` is no longer listening and the new login succeeds, close the old firewall rule:

```bash
sudo ufw delete allow 22/tcp
sudo ufw status verbose
```

Remove port `22` from the provider firewall as well. Never close the working session or port `22` before the custom-port login succeeds.

### Local SSH Shortcut

On your local computer, add this entry to `~/.ssh/config`:

```sshconfig
Host my-vps
    HostName YOUR_VPS_IP
    User deploy
    Port 2222
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

Then connect with:

```bash
ssh my-vps
```

### Recovery If Login Fails

Keep port `22` open and use the original session or provider console. On the VPS, inspect:

```bash
sudo sshd -t
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|allowusers) '
sudo ss -ltnp
sudo journalctl -u ssh.service -u ssh.socket --since today
```

Correct `/etc/ssh/sshd_config.d/00-hardening.conf`, validate it, then repeat the applicable restart command above. Do not disable password or root access before the administrative user's key login has been verified.

## 6. Configure Fail2ban

Run on the VPS and keep the port equal to the effective SSH port:

```bash
sudo tee /etc/fail2ban/jail.d/sshd.local > /dev/null <<'EOF'
[sshd]
enabled = true
port = 2222
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF
sudo chmod 644 /etc/fail2ban/jail.d/sshd.local
sudo fail2ban-client -t
```

If validation succeeds, load the configuration:

```bash
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
sudo fail2ban-client status sshd
```

## 7. Enable Security Updates And Set The Timezone

```bash
sudo dpkg-reconfigure unattended-upgrades
systemctl list-timers 'apt-daily*'
sudo timedatectl set-timezone UTC
timedatectl status
```

Use another timezone only when the server's operational requirements need it. UTC keeps logs easier to correlate.

## 8. Add Swap On A Small VPS

Check existing swap first:

```bash
swapon --show
```

If suitable swap already exists, skip this step. Otherwise create a 2 GiB swap file once:

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
swapon --show
```

## 9. Install Docker Engine And Compose

Use Docker's official Ubuntu repository:

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" |
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

The Docker group provides root-equivalent control. Add only the trusted administrative user:

```bash
sudo usermod -aG docker deploy
```

Log out and reconnect on port `2222`, then verify:

```bash
docker version
docker compose version
docker run --rm hello-world
```

Docker-published ports can bypass UFW. Bind private services to `127.0.0.1`, leave ports unpublished for container-only traffic, or protect them with the provider firewall.

## 10. Final Verification

```bash
sudo sshd -t
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|allowusers) '
sudo ufw status verbose
sudo fail2ban-client status sshd
ss -lntup
systemctl --failed
docker version
docker compose version
```

The expected SSH state is: only port `2222` is listening, root login is disabled, password and keyboard-interactive authentication are disabled, public-key authentication is enabled, and only the intended administrative users appear in `AllowUsers`.

## 11. Clone This Repository

The initial server setup is now complete. Clone the repository as the administrative user only when you are ready to install a service module:

```bash
git clone https://github.com/pthnhan/vps-setup.git "$HOME/vps-setup"
cd "$HOME/vps-setup"
```

Continue with [the database modules](../database/README.md).

## References

- [Ubuntu OpenSSH server](https://ubuntu.com/server/docs/how-to/security/openssh-server/)
- [Ubuntu firewall](https://ubuntu.com/server/docs/security-firewall/)
- [Ubuntu automatic security updates](https://documentation.ubuntu.com/security/security-updates/)
- [Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Docker firewall considerations](https://docs.docker.com/engine/network/packet-filtering-firewalls/)
