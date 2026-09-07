# PostgreSQL

Follow [database prerequisites](../README.md) first.

## 1. Configure — VPS

```bash
cd "$HOME/vps-setup"
export VPS_SETUP_SECRETS="$HOME/.config/vps-setup"
export POSTGRES_ENV_FILE="$VPS_SETUP_SECRETS/database/postgresql.env"
umask 077
mkdir -p "$VPS_SETUP_SECRETS/database"
test -e "$POSTGRES_ENV_FILE" || cp database/postgresql/.env.example "$POSTGRES_ENV_FILE"
chmod 600 "$POSTGRES_ENV_FILE"
nano "$POSTGRES_ENV_FILE"
```

Set `POSTGRES_PASSWORD` to a new password. Keep the bind IP at `127.0.0.1`.

## 2. Start — VPS

```bash
cd database/postgresql
docker network inspect database_network >/dev/null 2>&1 || docker network create database_network
docker compose --env-file "$POSTGRES_ENV_FILE" up -d --wait
docker compose --env-file "$POSTGRES_ENV_FILE" ps
```

## 3. Create A Project User — VPS

Use your configured admin username if you changed `postgres`.

```bash
docker compose --env-file "$POSTGRES_ENV_FILE" exec postgres psql -U postgres
```

Replace the project name, username, and password:

```sql
CREATE USER project_user WITH PASSWORD 'REPLACE_WITH_PROJECT_PASSWORD';
CREATE DATABASE project_db OWNER project_user;
REVOKE ALL ON DATABASE project_db FROM PUBLIC;
\q
```

## 4. Connect

**App on the VPS:**

```text
postgresql://project_user:PROJECT_PASSWORD@127.0.0.1:5432/project_db
```

**App in Docker:** replace `127.0.0.1` with `postgresql` and attach [database_network](../README.md#3-connect-an-application).

**Local workstation:** keep this tunnel running, then use the URI above:

```bash
ssh -o ExitOnForwardFailure=yes -N -L 5432:127.0.0.1:5432 vps
```

## 5. Back Up And Restore — VPS

Run from `~/vps-setup/database/postgresql`. In a new shell, set the env path first:

```bash
export POSTGRES_ENV_FILE="$HOME/.config/vps-setup/database/postgresql.env"
```

Back up:

```bash
umask 077
export BACKUP_DIR="$HOME/.local/state/vps-setup/backups"
mkdir -p "$BACKUP_DIR"
backup_tmp="$(mktemp "$BACKUP_DIR/project_db.sql.XXXXXX")"
docker compose --env-file "$POSTGRES_ENV_FILE" exec -T postgres pg_dump -U postgres project_db > "$backup_tmp" &&
  mv "$backup_tmp" "$BACKUP_DIR/project_db.sql"
```

After success, copy the backup off the VPS. On failure, inspect the error and temporary file before retrying.

Restore into an empty target database; create the project owner role separately:

```bash
export BACKUP_DIR="$HOME/.local/state/vps-setup/backups"
docker compose --env-file "$POSTGRES_ENV_FILE" exec -T postgres psql -v ON_ERROR_STOP=1 -U postgres project_db < "$BACKUP_DIR/project_db.sql"
```

## 6. Update — VPS

Back up first. Keep the current major image tag and run:

```bash
docker compose --env-file "$POSTGRES_ENV_FILE" pull
docker compose --env-file "$POSTGRES_ENV_FILE" up -d --wait
docker compose --env-file "$POSTGRES_ENV_FILE" ps
```

For a major upgrade, follow [PostgreSQL migration instructions](https://www.postgresql.org/docs/16/upgrading.html) and the [image volume requirements](https://hub.docker.com/_/postgres). Test the migration and restore before replacing production data.

See [service operations](../README.md#4-manage-a-service--vps) for logs, restarts, and stopping.
