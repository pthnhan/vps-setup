# VPS Setup Toolkit

A practical, security-first toolkit for preparing a new Ubuntu VPS and running reusable services with Docker Compose.

Read the initial setup guides in your browser and run their commands directly on the VPS. No clone, downloaded template, or repository working directory is needed until you install a service from `database/`.

## Repository Layout

```text
security/
  README.md
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
apt install -y sudo nano ca-certificates curl git gnupg htop unzip ufw fail2ban unattended-upgrades zsh build-essential
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
ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no deploy@YOUR_VPS_IP
```

In that new VPS session, verify administrative access:

```bash
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

Open [the SSH port and firewall guideline](security/README.md#avoid-ssh-lockout) in your browser and complete steps 1–4 there before continuing here. It contains the configuration inline, commands to run directly on the VPS, verification for both `ssh.service` and `ssh.socket`, and recovery instructions. No repository files are required.

### 4. Enable Brute-Force Protection And Security Updates

Follow [the direct Fail2ban setup](security/README.md#fail2ban), using the SSH port verified in step 3.

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

Only after the initial setup is verified, clone this repository as `deploy` on the VPS to use its Docker Compose modules:

```bash
git clone https://github.com/pthnhan/vps-setup.git "$HOME/vps-setup"
cd "$HOME/vps-setup"
```

If already cloned, enter your existing checkout instead. Run the example below from the repository root.

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
