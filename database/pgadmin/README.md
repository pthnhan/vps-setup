# pgAdmin

pgAdmin is a PostgreSQL-focused administration UI. Use it when you want deeper PostgreSQL workflows than a general database UI provides.

For a single UI that can connect to both PostgreSQL and MongoDB, use [DbGate](../dbgate/README.md).

## Start pgAdmin

Run these commands from the repository root.

Start PostgreSQL first, then start pgAdmin:

```bash
cd /home/pthnhan/workspace/vps-setup
export VPS_SETUP_SECRETS="$HOME/.config/vps-setup"
export PGADMIN_ENV_FILE="$VPS_SETUP_SECRETS/database/pgadmin.env"
mkdir -p "$VPS_SETUP_SECRETS/database"
cp database/pgadmin/.env.example "$PGADMIN_ENV_FILE"
chmod 600 "$PGADMIN_ENV_FILE"
nano "$PGADMIN_ENV_FILE"

cd database/pgadmin
docker network inspect database_network >/dev/null 2>&1 || docker network create database_network
docker compose --env-file "$PGADMIN_ENV_FILE" up -d
docker compose --env-file "$PGADMIN_ENV_FILE" ps
```

Change `PGADMIN_DEFAULT_EMAIL` and `PGADMIN_DEFAULT_PASSWORD` before starting the service.

By default, pgAdmin listens on `127.0.0.1:5050` on the VPS. This avoids exposing a database administration UI directly to the public internet.

## Open From Your Local Machine

Use an SSH tunnel:

```bash
ssh -L 5050:127.0.0.1:5050 deploy@YOUR_VPS_IP
```

Then open:

```text
http://127.0.0.1:5050
```

Log in with `PGADMIN_DEFAULT_EMAIL` and `PGADMIN_DEFAULT_PASSWORD` from the private env file.

## Add The PostgreSQL Server

In pgAdmin, choose **Add New Server**.

General tab:

```text
Name: PostgreSQL
```

Connection tab:

```text
Host name/address: postgresql
Port: 5432
Maintenance database: postgres
Username: project_user
Password: project_user_password
```

Use `postgresql` as the host when PostgreSQL is attached to the shared `database_network`. Prefer a project-specific database user for application databases. Use the PostgreSQL admin user only for maintenance tasks.

## Operations

Run these commands from `database/pgadmin`.

```bash
export PGADMIN_ENV_FILE="$HOME/.config/vps-setup/database/pgadmin.env"
docker compose --env-file "$PGADMIN_ENV_FILE" ps
docker compose --env-file "$PGADMIN_ENV_FILE" logs -f
docker compose --env-file "$PGADMIN_ENV_FILE" restart
docker compose --env-file "$PGADMIN_ENV_FILE" down
```

`docker compose down` keeps the named volume by default. pgAdmin settings are stored in the `pgadmin_data` Docker volume unless you change `PGADMIN_VOLUME_NAME`.

## Security Notes

- Keep `PGADMIN_BIND_IP=127.0.0.1` unless pgAdmin is behind a properly secured reverse proxy.
- Use a strong `PGADMIN_DEFAULT_PASSWORD`.
- Do not expose pgAdmin directly to the public internet.
- Use project-specific database users for application databases.
- Keep the real pgAdmin env file outside this repository, for example at `$HOME/.config/vps-setup/database/pgadmin.env`.
