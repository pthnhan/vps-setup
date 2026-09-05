# VPS Setup Toolkit

A practical, security-first toolkit for preparing a new Ubuntu VPS and running reusable services with Docker Compose.

## Repository Layout

```text
security/
  README.md
  sshd-hardening.conf.example
  fail2ban-sshd.local.example
database/
  README.md
  postgresql/
  mongodb/
  dbgate/
  pgadmin/
  mongo-express/
```

Keep real credentials outside this repository, under `$HOME/.config/vps-setup/`. Only `.env.example` templates belong here.

## Before You Start

- Use a current Ubuntu LTS image.
- Add your SSH public key through the VPS provider when possible.
- Keep the provider's web/serial console available until SSH hardening is verified.
- Take a provider snapshot before changing networking or SSH on an existing server.
- Replace every uppercase placeholder in the commands below.

## New VPS Checklist

Run the steps in order. Keep the original root SSH session open until a second session can log in with the new user, new SSH port, and SSH key.

### 1. Update The System

```bash
ssh root@YOUR_VPS_IP
```

After logging in to the VPS, run:

```bash
apt update
apt upgrade -y
apt install -y ca-certificates curl git gnupg htop unzip ufw fail2ban unattended-upgrades zsh build-essential
```

Reboot if required, then reconnect:

```bash
test -f /var/run/reboot-required && cat /var/run/reboot-required
```

### 2. Create An Administrative User

```bash
adduser deploy
usermod -aG sudo deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
if [ -f /root/.ssh/authorized_keys ]; then
  install -m 600 -o deploy -g deploy /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
fi
```

Open a second terminal and verify the key before continuing:

```bash
ssh deploy@YOUR_VPS_IP
sudo -v
```

If `/root/.ssh/authorized_keys` does not exist, add your public key directly to `/home/deploy/.ssh/authorized_keys` from the provider console.

### 3. Change The SSH Port And Configure The Firewall

Changing the port reduces automated log noise, but it is not a substitute for key authentication or a firewall. The safe order is:

1. Allow the new port in the provider firewall/security group.
2. Allow the new port in UFW while port 22 is still available.
3. Change and validate SSH configuration.
4. Test a new login on the new port.
5. Only then remove port 22.

The full copy-and-verify procedure is in [security/README.md](security/README.md). Example with TCP port `2222`:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH'
sudo ufw allow 22/tcp comment 'temporary SSH fallback'
sudo ufw logging low
sudo ufw enable
```

Install the SSH drop-in and replace the example port or user first:

```bash
sudo install -m 600 security/sshd-hardening.conf.example /etc/ssh/sshd_config.d/00-hardening.conf
sudo nano /etc/ssh/sshd_config.d/00-hardening.conf
sudo sshd -t
sudo systemctl restart ssh.service
```

Test from a new terminal:

```bash
ssh -p 2222 deploy@YOUR_VPS_IP
```

After that succeeds, remove the fallback rule:

```bash
sudo ufw delete allow 22/tcp
sudo ufw status numbered
```

Never close the working SSH session before the new login succeeds.

### 4. Enable Brute-Force Protection And Security Updates

Install the Fail2ban example, ensure its port matches SSH, then verify the jail:

```bash
sudo install -m 644 security/fail2ban-sshd.local.example /etc/fail2ban/jail.d/sshd.local
sudo nano /etc/fail2ban/jail.d/sshd.local
sudo fail2ban-client -t
sudo systemctl enable --now fail2ban
sudo fail2ban-client status sshd
```

Enable automatic security updates and check their timers:

```bash
sudo dpkg-reconfigure unattended-upgrades
systemctl list-timers 'apt-daily*'
```

### 5. Set Timezone And Add Swap

UTC makes server logs and incident timelines easier to correlate:

```bash
sudo timedatectl set-timezone UTC
timedatectl status
```

For a small VPS without swap, create a 2 GiB swap file once:

```bash
swapon --show
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
sudo swapon --show
```

Skip creation if `swapon --show` already lists suitable swap. Do not append `/etc/fstab` twice.

### 6. Install Docker Engine And Compose

Use Docker's official Ubuntu repository for a production host; its package names are `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, and `docker-compose-plugin`. Follow the current [official Ubuntu installation instructions](https://docs.docker.com/engine/install/ubuntu/) rather than a convenience script.

Add the deployment user only if it should have root-equivalent Docker control:

```bash
sudo usermod -aG docker deploy
```

Log out and back in, then verify:

```bash
docker version
docker compose version
docker run --rm hello-world
```

Docker-published ports can bypass UFW. Keep internal services bound to `127.0.0.1` or unpublish their ports; do not rely on a UFW deny rule to protect a port published on `0.0.0.0`.

### 7. Final Verification

```bash
sudo sshd -t
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication) '
sudo ufw status verbose
sudo fail2ban-client status sshd
ss -lntup
systemctl --failed
```

Also verify the provider firewall exposes only the ports you intend to use. Normally that is the custom SSH port plus `80/tcp` and `443/tcp` when a public web server is installed.

### 8. Optional Interactive Shell

For a VPS used interactively, change the deployment user's shell only after the core setup is complete:

```bash
sudo chsh -s "$(command -v zsh)" deploy
```

Shell frameworks and plugins are optional. Review remote install scripts before running them, keep configuration per user, and avoid adding language-runtime paths that are not actually installed.

## Using Service Modules

Create only the private env files for services you run:

```text
$HOME/.config/vps-setup/database/postgresql.env
$HOME/.config/vps-setup/database/mongodb.env
$HOME/.config/vps-setup/database/dbgate.env
$HOME/.config/vps-setup/database/pgadmin.env
$HOME/.config/vps-setup/database/mongo-express.env
```

Example:

```bash
export VPS_SETUP_SECRETS="$HOME/.config/vps-setup"
mkdir -p "$VPS_SETUP_SECRETS/database"
cp database/postgresql/.env.example "$VPS_SETUP_SECRETS/database/postgresql.env"
chmod 600 "$VPS_SETUP_SECRETS/database/postgresql.env"
nano "$VPS_SETUP_SECRETS/database/postgresql.env"

cd database/postgresql
docker network inspect database_network >/dev/null 2>&1 || docker network create database_network
docker compose --env-file "$VPS_SETUP_SECRETS/database/postgresql.env" config --quiet
docker compose --env-file "$VPS_SETUP_SECRETS/database/postgresql.env" up -d
docker compose --env-file "$VPS_SETUP_SECRETS/database/postgresql.env" ps
```

Read [database/README.md](database/README.md) before installing a database. Install a database service once, then give each application its own database, user, password, and connection string.

## Common Operations

Inside a service folder:

```bash
export SERVICE_ENV_FILE="$HOME/.config/vps-setup/database/postgresql.env"
docker compose --env-file "$SERVICE_ENV_FILE" ps
docker compose --env-file "$SERVICE_ENV_FILE" logs -f
docker compose --env-file "$SERVICE_ENV_FILE" restart
docker compose --env-file "$SERVICE_ENV_FILE" down
```

`docker compose down` keeps named volumes unless `--volumes` is supplied. Back up important data off the VPS before upgrades.
