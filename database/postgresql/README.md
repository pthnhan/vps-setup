# PostgreSQL

This module runs one PostgreSQL service for the VPS. Install it once, then create a separate database and user for each application project.

## Start PostgreSQL

Run these commands from the repository root.

```bash
cd /home/pthnhan/workspace/vps-setup
export VPS_SETUP_SECRETS="$HOME/.config/vps-setup"
export POSTGRES_ENV_FILE="$VPS_SETUP_SECRETS/database/postgresql.env"
mkdir -p "$VPS_SETUP_SECRETS/database"
cp database/postgresql/.env.example "$POSTGRES_ENV_FILE"
chmod 600 "$POSTGRES_ENV_FILE"
nano "$POSTGRES_ENV_FILE"

cd database/postgresql
docker network inspect database_network >/dev/null 2>&1 || docker network create database_network
docker compose --env-file "$POSTGRES_ENV_FILE" up -d
docker compose --env-file "$POSTGRES_ENV_FILE" ps
```

Change `POSTGRES_PASSWORD` before starting the service.

By default, PostgreSQL listens on `127.0.0.1:5432` on the VPS. This is safer than exposing it publicly.

## Public Access From Your Local Machine

Use this only when external machines must connect directly to PostgreSQL. Setting `POSTGRES_BIND_IP=0.0.0.0` exposes the PostgreSQL port on all VPS network interfaces.

Edit the private PostgreSQL environment file:

```bash
export POSTGRES_ENV_FILE="$HOME/.config/vps-setup/database/postgresql.env"
nano "$POSTGRES_ENV_FILE"
```

Set:

```dotenv
POSTGRES_BIND_IP=0.0.0.0
POSTGRES_PORT=5432
```

Restart only this PostgreSQL service:

```bash
cd database/postgresql
docker compose --env-file "$POSTGRES_ENV_FILE" up -d
docker compose --env-file "$POSTGRES_ENV_FILE" ps
docker port postgresql 5432
```

Confirm PostgreSQL is listening publicly on the VPS:

```bash
ss -ltnp | grep ':5432'
```

Expected listener:

```text
0.0.0.0:5432
```

If the VPS firewall is enabled, allow remote PostgreSQL access:

```bash
sudo ufw allow 5432/tcp
sudo ufw status
```

If the VPS provider has a cloud firewall or security group, also open inbound TCP port `5432` there.

Connect from a local database client with:

```text
host: VPS_PUBLIC_IP
port: 5432
database: project_db
user: project_user
password: project_user_password
```

For the crypto trading project on this VPS:

```text
host: 43.228.213.109
port: 5432
database: crypto_trading_system
user: crypto_user
password: POSTGRES_PASSWORD from /home/pthnhan/workspace/crypto_trading_system/.env
```

Use the project user, not the PostgreSQL admin user. If the connection is refused, check the Docker bind address, `ufw`, and the VPS provider firewall. If authentication fails, rotate or recheck the project user's password.

## Create A Database For A New Project

Open `psql` as the PostgreSQL admin user from the private env file:

```bash
export POSTGRES_ENV_FILE="$HOME/.config/vps-setup/database/postgresql.env"
docker compose --env-file "$POSTGRES_ENV_FILE" exec postgres psql -U postgres
```

Create a project user and database:

```sql
CREATE USER project_user WITH PASSWORD 'change_this_project_password';
CREATE DATABASE project_db OWNER project_user;
GRANT ALL PRIVILEGES ON DATABASE project_db TO project_user;
\q
```

Use one unique database and user per app. For example, a project named `crm-api` might use:

```sql
CREATE USER crm_api_user WITH PASSWORD 'use_a_long_random_password';
CREATE DATABASE crm_api OWNER crm_api_user;
GRANT ALL PRIVILEGES ON DATABASE crm_api TO crm_api_user;
\q
```

## Connection Strings

For an app connecting through the VPS host or IP:

```text
DATABASE_URL=postgresql://project_user:change_this_project_password@VPS_HOST:5432/project_db
```

For an app running in Docker on the same VPS and attached to `database_network`:

```text
DATABASE_URL=postgresql://project_user:change_this_project_password@postgresql:5432/project_db
```

Example app Compose network configuration:

```yaml
services:
  app:
    image: your-app-image
    networks:
      - default
      - database_network

networks:
  database_network:
    external: true
    name: database_network
```

Store the connection string in the application's `.env` file or secret manager.

If you change `DATABASE_NETWORK_NAME` in the private env file, create that Docker network name instead of `database_network`.

## Operations

Run these commands from `database/postgresql`.

```bash
export POSTGRES_ENV_FILE="$HOME/.config/vps-setup/database/postgresql.env"
docker compose --env-file "$POSTGRES_ENV_FILE" ps
docker compose --env-file "$POSTGRES_ENV_FILE" logs -f
docker compose --env-file "$POSTGRES_ENV_FILE" restart
docker compose --env-file "$POSTGRES_ENV_FILE" down
```

`docker compose down` keeps the named volume by default. The database data is stored in the `postgres_data` Docker volume unless you change `POSTGRES_VOLUME_NAME`.

## Backup And Restore

Create a backup for one project database:

```bash
mkdir -p backups
docker compose --env-file "$POSTGRES_ENV_FILE" exec -T postgres pg_dump -U postgres project_db > backups/project_db.sql
```

Restore a backup:

```bash
docker compose --env-file "$POSTGRES_ENV_FILE" exec -T postgres psql -U postgres project_db < backups/project_db.sql
```

For larger production databases, use a scheduled backup job and copy backup files off the VPS.

## Upgrade Notes

1. Back up every important database.
2. Read the PostgreSQL Docker image release notes for the target major version.
3. Update the image tag in `docker-compose.yml`.
4. Run `docker compose pull`.
5. Restart with `docker compose --env-file "$POSTGRES_ENV_FILE" up -d`.

Major PostgreSQL upgrades can require a dump/restore or `pg_upgrade`. Do not change major versions casually on a production database.

## Security Notes

- Keep `POSTGRES_BIND_IP=127.0.0.1` unless remote access is required.
- If remote access is required, prefer restricting the firewall to trusted source IPs.
- If you intentionally allow all IPs, use strong project-user passwords, keep backups, and monitor logs.
- Use a unique database user and strong password for each project.
- Do not reuse the admin password as an application password.
- Keep the real PostgreSQL env file outside this repository, for example at `$HOME/.config/vps-setup/database/postgresql.env`.
