# PostgreSQL

This module runs one PostgreSQL service for the VPS. Install it once, then create a separate database and user for each application project.

## Start PostgreSQL

Run these commands from the repository root.

```bash
cd /path/to/vps-setup
export VPS_SETUP_SECRETS="$HOME/.config/vps-setup"
export POSTGRES_ENV_FILE="$VPS_SETUP_SECRETS/database/postgresql.env"
umask 077
mkdir -p "$VPS_SETUP_SECRETS/database"
test -e "$POSTGRES_ENV_FILE" || cp database/postgresql/.env.example "$POSTGRES_ENV_FILE"
chmod 600 "$POSTGRES_ENV_FILE"
nano "$POSTGRES_ENV_FILE"

cd database/postgresql
docker network inspect database_network >/dev/null 2>&1 || docker network create database_network
docker compose --env-file "$POSTGRES_ENV_FILE" up -d
docker compose --env-file "$POSTGRES_ENV_FILE" ps
```

Change `POSTGRES_PASSWORD` before starting the service.

By default, PostgreSQL listens on `127.0.0.1:5432` on the VPS. This is safer than exposing it publicly.

## Access From Your Local Machine

Keep `POSTGRES_BIND_IP=127.0.0.1` and create an SSH tunnel from your local machine:

```bash
ssh -i ~/.ssh/id_ed25519_vps -o ExitOnForwardFailure=yes -N -L 5432:127.0.0.1:5432 -p SSH_PORT deploy@YOUR_VPS_IP
```

Then connect the local database client to:

```text
host: 127.0.0.1
port: 5432
database: project_db
user: project_user
password: project_user_password
```

The tunnel encrypts the connection and avoids a public database listener. Use the project user, not the PostgreSQL admin user.

If a separate application server must connect, prefer a private network or VPN. As a last resort, bind PostgreSQL publicly and restrict TCP `5432` in the VPS provider firewall to the exact trusted source IP. Do not rely only on UFW: Docker-published ports can bypass UFW rules.

Confirm the actual listener whenever changing the bind address:

```bash
docker port postgresql 5432
ss -ltnp | grep ':5432'
```

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
REVOKE ALL ON DATABASE project_db FROM PUBLIC;
\q
```

Use one unique database and user per app. For example, a project named `crm-api` might use:

```sql
CREATE USER crm_api_user WITH PASSWORD 'use_a_long_random_password';
CREATE DATABASE crm_api OWNER crm_api_user;
REVOKE ALL ON DATABASE crm_api FROM PUBLIC;
\q
```

## Connection Strings

For an app running directly on the VPS host:

```text
DATABASE_URL=postgresql://project_user:change_this_project_password@127.0.0.1:5432/project_db
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
umask 077
export BACKUP_DIR="$HOME/.local/state/vps-setup/backups"
mkdir -p "$BACKUP_DIR"
backup_tmp="$(mktemp "$BACKUP_DIR/project_db.sql.XXXXXX")"
docker compose --env-file "$POSTGRES_ENV_FILE" exec -T postgres pg_dump -U postgres project_db > "$backup_tmp" &&
  mv "$backup_tmp" "$BACKUP_DIR/project_db.sql"
```

On dump failure, the last successful backup remains unchanged; inspect/remove the temporary file. Copy successful backups off the VPS.

Restore into an existing empty `project_db` after creating its owner role (as above). This restores data/objects, not cluster roles:

```bash
docker compose --env-file "$POSTGRES_ENV_FILE" exec -T postgres psql -v ON_ERROR_STOP=1 -U postgres project_db < "$BACKUP_DIR/project_db.sql"
```

For larger production databases, use a scheduled backup job and copy backup files off the VPS.

## Upgrade Notes

1. Back up every important database.
2. Read the PostgreSQL Docker image release notes for the target major version.
3. For a patch update within the current major version, keep the existing image tag. For a major upgrade, complete the database-specific migration procedure with a tested backup and a separate target volume; the pull/recreate commands below do not migrate data.
4. Run `docker compose --env-file "$POSTGRES_ENV_FILE" pull`.
5. Restart with `docker compose --env-file "$POSTGRES_ENV_FILE" up -d`.

The current PostgreSQL 16 volume mounts at `/var/lib/postgresql/data`. PostgreSQL 18+ changes its volume layout; follow the [official image migration notes](https://hub.docker.com/_/postgres) before switching majors.

Major PostgreSQL upgrades can require a dump/restore or `pg_upgrade`. Do not change major versions casually on a production database.

## Security Notes

- Keep `POSTGRES_BIND_IP=127.0.0.1` unless remote access is required.
- Prefer an SSH tunnel, VPN, or private network for remote access.
- Docker ports published on `0.0.0.0` can bypass UFW; do not treat UFW as the only protection for a public database listener.
- Use a unique database user and strong password for each project.
- Do not reuse the admin password as an application password.
- Keep the real PostgreSQL env file outside this repository, for example at `$HOME/.config/vps-setup/database/postgresql.env`.
