# VPS Setup Toolkit

This repository is a practical checklist and collection of small install modules for a new VPS. The goal is simple: prepare a server once, then install only the tools each project needs.

The first tool category is `database/`, with separate Docker Compose examples for PostgreSQL, MongoDB, and optional database web UIs.

## Repository Layout

```text
database/
  README.md
  postgresql/
    docker-compose.yml
    .env.example
    README.md
  mongodb/
    docker-compose.yml
    .env.example
    README.md
  dbgate/
    docker-compose.yml
    .env.example
    README.md
  pgadmin/
    docker-compose.yml
    .env.example
    README.md
  mongo-express/
    docker-compose.yml
    .env.example
    README.md
```

Each installable tool should live in its own folder. Keep real environment files outside this repository, then start each tool with Docker Compose's `--env-file` option.


## Environment File Policy

Keep only templates in this repository:

```text
database/*/.env.example
```

Keep real service environment files outside the repository. Create only the files for services you actually run:

```text
$HOME/.config/vps-setup/database/postgresql.env
$HOME/.config/vps-setup/database/mongodb.env
$HOME/.config/vps-setup/database/dbgate.env
$HOME/.config/vps-setup/database/pgadmin.env
$HOME/.config/vps-setup/database/mongo-express.env
```

Application environment files belong to the application repository or its secret manager. For example, `<your_new_project>/.env` may contain that app project user credentials for PostgreSQL and MongoDB. It should not contain the VPS service admin passwords or DBGate UI password.

If a real `.env` file is accidentally created inside this repository, move it to the private directory or delete it after confirming the private copy exists:

```bash
find database -maxdepth 2 -name .env -print
```

## New VPS Setup Checklist

These commands assume an Ubuntu or Debian-based VPS. Adjust package names if your server uses another distribution.

### 1. Log In And Update Packages

```bash
ssh root@YOUR_VPS_IP

apt update
apt upgrade -y
apt install -y curl git unzip htop ufw fail2ban ca-certificates gnupg zsh build-essential
```

`build-essential` installs `gcc`, `g++`, `make`, and common build dependencies. Prefer it over installing compiler packages one by one.

### 2. Create A Non-Root User

```bash
adduser deploy
usermod -aG sudo deploy
```

Copy your SSH public key to the new user before disabling password login:

```bash
rsync --archive --chown=deploy:deploy ~/.ssh /home/deploy
```

Then reconnect as the new user:

```bash
ssh deploy@YOUR_VPS_IP
```

### 3. Harden SSH

Make sure SSH key login works before changing SSH settings.

```bash
sudo nano /etc/ssh/sshd_config.d/99-hardening.conf
```

Recommended settings:

```text
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```

Reload SSH:

```bash
sudo systemctl reload ssh
```

Keep your current SSH session open while testing a new login window.

### 4. Configure Firewall

```bash
sudo ufw allow OpenSSH
sudo ufw enable
sudo ufw status
```

Only open service ports when a project really needs public access. For databases, prefer private access through localhost, a VPN, or a shared Docker network.

### 5. Set Timezone And Swap

```bash
sudo timedatectl set-timezone UTC
```

For small VPS instances, add swap:

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### 6. Install Docker And Compose

Quick setup with distribution packages:

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-plugin
sudo usermod -aG docker "$USER"
```

Log out and back in, then verify:

```bash
docker --version
docker compose version
```

For production servers that need the newest Docker release, use Docker's official installation instructions for your distribution.

### 7. Optional Developer Tooling And Shell

Use this section when the VPS will also be used for interactive development or project maintenance.

| Category | Tools or settings | Notes |
| --- | --- | --- |
| Core CLI packages | `curl`, `git`, `zsh` | Useful on most servers and installed in step 1. |
| Build tools | `build-essential` | Includes `gcc`, `g++`, `make`, and common build headers. |
| GUI terminal | `terminator` | Install only on a VPS with a desktop environment or X11 forwarding. |
| Shell framework | Oh My Zsh | Per-user shell customization for `zsh`. |
| Shell plugin | `zsh-autosuggestions` | Adds command suggestions based on shell history. |
| User shell config | `PATH`, `ZSH_THEME`, `plugins` | Stored in the user's `~/.zshrc`. |

If you skipped the packages in step 1, install them now:

```bash
sudo apt update
sudo apt install -y curl git zsh build-essential
```

`sudo apt-get install gcc gcc+` is not valid on Ubuntu or Debian because `gcc+` is not a package name. Use `build-essential`, or install `gcc g++` directly if you only need the compilers.

Install `terminator` only when the VPS has a graphical desktop session:

```bash
sudo apt install -y terminator
```

Run the shell setup as the non-root user that will use `zsh`:

```bash
sudo chsh -s "$(command -v zsh)" "$USER"
RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
```

Then update `~/.zshrc`:

```zsh
export PATH="$HOME/miniconda3/bin:$PATH"
ZSH_THEME="gnzh"
plugins=(git zsh-autosuggestions)
```

The `PATH` line is only needed if Miniconda is installed at `$HOME/miniconda3`. Replace the default `plugins=(git)` line instead of adding a second `plugins` line.

Apply the settings:

```bash
source ~/.zshrc
```

Log out and reconnect to confirm the default shell changed.

## Using This Repository

1. Choose the tool you want to install.
2. Copy that tool's `.env.example` to a private path outside this repository.
3. Edit passwords, ports, names, and bind addresses in the private env file.
4. Enter the tool folder.
5. Start the service with `docker compose --env-file`.

Example:

```bash
cd /home/pthnhan/workspace/vps-setup
export VPS_SETUP_SECRETS="$HOME/.config/vps-setup"
mkdir -p "$VPS_SETUP_SECRETS/database"
cp database/postgresql/.env.example "$VPS_SETUP_SECRETS/database/postgresql.env"
chmod 600 "$VPS_SETUP_SECRETS/database/postgresql.env"
nano "$VPS_SETUP_SECRETS/database/postgresql.env"

cd database/postgresql
docker network inspect database_network >/dev/null 2>&1 || docker network create database_network
docker compose --env-file "$VPS_SETUP_SECRETS/database/postgresql.env" up -d
docker compose --env-file "$VPS_SETUP_SECRETS/database/postgresql.env" ps
```

## Databases

Read [database/README.md](database/README.md) before starting a database service.

The important model is:

- Install PostgreSQL, MongoDB, or another database service once on the VPS.
- For every new project, create a separate database, user, password, and connection string.
- Store each project's connection string in that project's own environment file or secret manager.

Current database service modules:

- [PostgreSQL](database/postgresql/README.md)
- [MongoDB](database/mongodb/README.md)

Current database UI modules:

- [DbGate](database/dbgate/README.md): recommended general-purpose UI for PostgreSQL and MongoDB.
- [pgAdmin](database/pgadmin/README.md): PostgreSQL-focused administration UI.
- [mongo-express](database/mongo-express/README.md): MongoDB-only UI for private development or short-lived maintenance.

For direct PostgreSQL access from a local machine, read the public access section in [database/postgresql/README.md](database/postgresql/README.md). The short version is: set `POSTGRES_BIND_IP=0.0.0.0` in the private PostgreSQL env file, restart the PostgreSQL Compose service with `--env-file`, open TCP port `5432` in the VPS firewall and provider firewall, then connect to `VPS_PUBLIC_IP:5432` with the project database user.

## Common Operations

Inside any service folder:

```bash
export SERVICE_ENV_FILE="$HOME/.config/vps-setup/database/postgresql.env"
docker compose --env-file "$SERVICE_ENV_FILE" ps
docker compose --env-file "$SERVICE_ENV_FILE" logs -f
docker compose --env-file "$SERVICE_ENV_FILE" restart
docker compose --env-file "$SERVICE_ENV_FILE" down
```

`docker compose down` stops containers but keeps named volumes by default. Do not remove volumes unless you intentionally want to delete persistent data.
