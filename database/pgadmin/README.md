# pgAdmin

Follow [database prerequisites](../README.md) first.

## 1. Configure — VPS

Start [PostgreSQL](../postgresql/README.md) first.

```bash
cd "$HOME/vps-setup"
export VPS_SETUP_SECRETS="$HOME/.config/vps-setup"
export PGADMIN_ENV_FILE="$VPS_SETUP_SECRETS/database/pgadmin.env"
umask 077
mkdir -p "$VPS_SETUP_SECRETS/database"
test -e "$PGADMIN_ENV_FILE" || cp database/pgadmin/.env.example "$PGADMIN_ENV_FILE"
chmod 600 "$PGADMIN_ENV_FILE"
nano "$PGADMIN_ENV_FILE"
```

Set `PGADMIN_DEFAULT_PASSWORD` to a new password. Keep the bind IP at `127.0.0.1`. Set `PGADMIN_DEFAULT_EMAIL` to your login email.

## 2. Start — VPS

```bash
cd database/pgadmin
docker network inspect database_network >/dev/null 2>&1 || docker network create database_network
docker compose --env-file "$PGADMIN_ENV_FILE" up -d
docker compose --env-file "$PGADMIN_ENV_FILE" ps
```

## 3. Open — Local

Keep this tunnel running:

```bash
ssh -o ExitOnForwardFailure=yes -N -L 5050:127.0.0.1:5050 vps
```

Open `http://127.0.0.1:5050` and log in with `PGADMIN_DEFAULT_EMAIL` / `PGADMIN_DEFAULT_PASSWORD`.

## 4. Register A Server

Select **Add New Server** and enter:

| Field | Value |
| --- | --- |
| Name | Project PostgreSQL |
| Host name/address | `postgresql` |
| Port | `5432` |
| Maintenance database | `project_db` |
| Username | `project_user` |
| Password | Project database password |

See [service operations](../README.md#4-manage-a-service--vps) for logs, restarts, and stopping.
