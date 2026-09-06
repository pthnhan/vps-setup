# VPS Security Baseline

This guide targets a new Ubuntu VPS managed over SSH. Use the VPS provider's firewall as the outer layer and UFW as the host firewall.

Read this page in your browser and run the commands directly on the VPS as the administrative user (`deploy` below). You do not need to clone this repository or download any template. First complete [system updates and administrative user creation](../README.md#new-vps-checklist), and verify SSH key login and `sudo` for that user.

## Avoid SSH Lockout

Keep one working SSH session open throughout this procedure. Make sure the provider's web or serial console works before changing SSH.

These steps assume the initial SSH port is `22`. If your provider uses another port, substitute it wherever `22` appears, including the temporary firewall rules and socket configuration.

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

### 2. Create The SSH Configuration Directly

Keep both ports listening until the new login is verified. Replace `2222` and `deploy` below with your chosen port and administrative user **before running** the command. On an existing server, back up any existing `00-hardening.conf` before replacing it.

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

List all intended SSH users on `AllowUsers`, separated by spaces. The `00-` prefix is intentional: OpenSSH uses the first value for most directives, so this file must precede cloud-image defaults such as `50-cloud-init.conf`.

Validate before applying:

```bash
sudo sshd -t
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|allowusers) '
```

Stop if validation fails or effective settings differ from the configuration above. Check `/etc/ssh/sshd_config` and its included files for earlier settings, extra `Port` entries, or applicable `Match` blocks before continuing.

Check whether systemd owns the SSH listening socket:

```bash
systemctl is-active ssh.socket
```

If it prints `active`, create a socket override with the same two ports. Back up an existing `99-listen.conf` before replacing it:

```bash
sudo install -d -m 755 /etc/systemd/system/ssh.socket.d
sudo tee /etc/systemd/system/ssh.socket.d/99-listen.conf > /dev/null <<'EOF'
[Socket]
ListenStream=
ListenStream=22
ListenStream=2222
EOF
sudo systemctl daemon-reload
sudo systemctl restart ssh.socket ssh.service
```

The empty `ListenStream=` clears inherited listeners. This explicit override also covers images where changing `Port` in `sshd_config` alone does not update the socket.

If `ssh.socket` is inactive or not found, apply the validated configuration with:

```bash
sudo systemctl restart ssh.service
```

For either mode, verify that both ports are listening; the socket may be owned by systemd rather than `sshd`:

```bash
sudo ss -ltnp
```

### 3. Test A New Login

From a different local terminal:

```bash
ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no -p 2222 deploy@YOUR_VPS_IP
```

Inside that new VPS session:

```bash
sudo -v
```

Confirm that key login and `sudo` both work. Do not use the existing session as proof because an established connection can survive a broken SSH configuration.

### 4. Close Port 22

Only after the new key login and `sudo` succeed, remove the `Port 22` line from `/etc/ssh/sshd_config.d/00-hardening.conf`. If you created the socket override, also remove `ListenStream=22` from `/etc/systemd/system/ssh.socket.d/99-listen.conf`; keep the empty `ListenStream=` and `ListenStream=2222` lines.

Run `sudo sshd -t` again, then repeat the applicable restart commands from step 2 (including `daemon-reload` for socket mode). Check `sudo sshd -T` and `sudo ss -ltnp`: SSH should now listen only on the new port. If port 22 remains, find and remove its other explicit `Port` or socket listener entry before proceeding. Test a fresh login on port `2222` again, then remove the fallback firewall rule:

```bash
sudo ufw delete allow 22/tcp
sudo ufw status numbered
```

Remove TCP `22` from the provider firewall too. Keep only the custom SSH port and application ports that are intentionally public.

On your local computer, add this entry to `~/.ssh/config` for convenience (use the path to your actual private key):

```sshconfig
Host my-vps
    HostName YOUR_VPS_IP
    User deploy
    Port 2222
    IdentityFile ~/.ssh/id_ed25519
```

Then connect with `ssh my-vps`.

### Recovery If The New Login Fails

Keep port 22 allowed in both firewalls and keep the original session open. Inspect `sudo journalctl -u ssh.service -u ssh.socket --since today`, the effective SSH settings, and `sudo ss -ltnp`. Correct the configuration, validate, and repeat the applicable restart commands from step 2. If you need to revert, restore the previous files (or remove only the files created by this procedure on a fresh VPS) and apply the same validation and restart steps. Use the provider console if no SSH session remains available. Do not close port 22 until the new login succeeds.

## Fail2ban

Create the jail directly on the VPS. Replace `2222` with the verified SSH port before running this block; back up any existing `sshd.local` before replacing it:

```bash
sudo apt install -y fail2ban
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

Only if validation succeeds, enable and restart Fail2ban so an already-running service also loads the new jail:

```bash
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
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
- [Ubuntu SSH socket activation](https://discourse.ubuntu.com/t/sshd-now-uses-socket-based-activation-ubuntu-22-10-and-later/30189)
- [Ubuntu firewall guide](https://ubuntu.com/server/docs/security-firewall/)
- [Ubuntu automatic security updates](https://documentation.ubuntu.com/security/security-updates/)
- [Docker firewall limitations](https://docs.docker.com/engine/network/packet-filtering-firewalls/)
