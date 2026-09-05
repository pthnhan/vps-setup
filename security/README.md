# VPS Security Baseline

This guide targets a new Ubuntu VPS managed over SSH. Use the VPS provider's firewall as the outer layer and UFW as the host firewall.

## Avoid SSH Lockout

Keep one working SSH session open throughout this procedure. Make sure the provider's web or serial console works before changing SSH.

Choose an unused port from `1024` to `65535`. This guide uses `2222`; replace it everywhere if you choose another port.

### 1. Open The New Port First

Allow inbound TCP `2222` in the provider firewall/security group. If the provider firewall supports source restrictions and your public IP is stable, restrict SSH to that IP.

Then configure UFW while the existing SSH port is still open:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH'
sudo ufw allow 22/tcp comment 'temporary SSH fallback'
sudo ufw logging low
sudo ufw enable
sudo ufw status verbose
```

`ufw limit` rate-limits repeated connection attempts. Fail2ban adds longer bans based on authentication failures.

### 2. Install The SSH Drop-In

From the repository root:

```bash
sudo install -m 600 security/sshd-hardening.conf.example /etc/ssh/sshd_config.d/00-hardening.conf
sudo nano /etc/ssh/sshd_config.d/00-hardening.conf
```

Set `Port` to the port opened above. Set `AllowUsers` to the actual administrative user, or remove that line if multiple users need SSH access.

The `00-` prefix is intentional. OpenSSH uses the first value it reads for most directives, and Ubuntu cloud images can include an earlier `50-cloud-init.conf`; a `99-` hardening file may therefore fail to override it.

Validate the full SSH configuration before restart:

```bash
sudo sshd -t
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|allowusers) '
sudo systemctl restart ssh.service
sudo ss -ltnp | grep sshd
```

If `sshd -t` prints an error, fix it before restarting. On Debian and Ubuntu the systemd service is normally named `ssh.service`; confirm with `systemctl status ssh.service`.

### 3. Test A New Login

From a different local terminal:

```bash
ssh -p 2222 deploy@YOUR_VPS_IP
sudo -v
```

Confirm that key login and `sudo` both work. Do not use the existing session as proof because an established connection can survive a broken SSH configuration.

### 4. Close Port 22

Only after the new login succeeds:

```bash
sudo ufw delete allow 22/tcp
sudo ufw status numbered
```

Remove TCP `22` from the provider firewall too. Keep only the custom SSH port and application ports that are intentionally public.

Update local SSH configuration for convenience:

```sshconfig
Host my-vps
    HostName YOUR_VPS_IP
    User deploy
    Port 2222
    IdentityFile ~/.ssh/id_ed25519
```

Then connect with `ssh my-vps`.

## Fail2ban

Install the example and make its port match the effective SSH port:

```bash
sudo apt install -y fail2ban
sudo install -m 644 security/fail2ban-sshd.local.example /etc/fail2ban/jail.d/sshd.local
sudo nano /etc/fail2ban/jail.d/sshd.local
sudo fail2ban-client -t
sudo systemctl enable --now fail2ban
sudo fail2ban-client status sshd
```

Check recent bans and service errors with:

```bash
sudo journalctl -u fail2ban --since today
sudo fail2ban-client status sshd
```

Fail2ban is defense in depth. SSH keys, disabled password login, and firewall rules remain the primary controls.

## Public Ports

Open web ports only after a web server or reverse proxy is installed:

```bash
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
```

Prefer these exposure patterns:

| Service | Recommended exposure |
| --- | --- |
| SSH | Custom TCP port, rate-limited; source-restricted when practical |
| HTTP/HTTPS | Public `80/tcp` and `443/tcp` through a reverse proxy |
| Database | Docker network or `127.0.0.1` plus SSH/VPN tunnel |
| Database UI | `127.0.0.1` plus SSH tunnel |
| Docker daemon | Unix socket only; never unauthenticated public TCP |

For a service restricted to one trusted public IP, a normal host process can use:

```bash
sudo ufw allow proto tcp from TRUSTED_PUBLIC_IP to any port SERVICE_PORT
```

This is not sufficient for Docker ports published on `0.0.0.0`: Docker documents that published container traffic can bypass UFW. Prefer a loopback bind such as `127.0.0.1:5432:5432`, no published port for container-to-container traffic, a provider firewall, or carefully maintained `DOCKER-USER` rules.

Do not set Docker's `iptables` option to `false`; Docker warns that this commonly breaks container networking.

## Automatic Security Updates

Ubuntu Server normally includes `unattended-upgrades`. Enable it and verify the timers:

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure unattended-upgrades
systemctl list-timers 'apt-daily*'
sudo unattended-upgrade --dry-run --debug
```

Logs are under `/var/log/unattended-upgrades/`. Automatic reboot is not enabled by this repository; schedule reboots deliberately when `/var/run/reboot-required` exists.

## Ongoing Checks

Run these after changes and periodically:

```bash
sudo sshd -t
sudo ufw status verbose
sudo fail2ban-client status sshd
ss -lntup
docker ps --format 'table {{.Names}}\t{{.Ports}}'
systemctl --failed
journalctl -p warning --since today
```

Review the provider firewall separately; it is not visible in UFW output.

## References

- [Ubuntu OpenSSH server guide](https://ubuntu.com/server/docs/how-to/security/openssh-server/)
- [Ubuntu firewall guide](https://ubuntu.com/server/docs/security-firewall/)
- [Ubuntu automatic security updates](https://documentation.ubuntu.com/security/security-updates/)
- [Docker firewall limitations](https://docs.docker.com/engine/network/packet-filtering-firewalls/)
