# DbGate

DbGate is the recommended general-purpose database UI for this repository. It can connect to both PostgreSQL and MongoDB, so one web UI can manage both database modules.

Use DbGate when you want one interface for multiple database engines. Use pgAdmin when you specifically want PostgreSQL-focused administration features. Use mongo-express only for private development workflows.

## Start DbGate

Run these commands from the repository root.

Start PostgreSQL and/or MongoDB first, then start DbGate:

```bash
cd /path/to/vps-setup
export VPS_SETUP_SECRETS="$HOME/.config/vps-setup"
export DBGATE_ENV_FILE="$VPS_SETUP_SECRETS/database/dbgate.env"
mkdir -p "$VPS_SETUP_SECRETS/database"
cp database/dbgate/.env.example "$DBGATE_ENV_FILE"
chmod 600 "$DBGATE_ENV_FILE"
nano "$DBGATE_ENV_FILE"

cd database/dbgate
docker network inspect database_network >/dev/null 2>&1 || docker network create database_network
docker compose --env-file "$DBGATE_ENV_FILE" up -d
docker compose --env-file "$DBGATE_ENV_FILE" ps
```

Change `DBGATE_PASSWORD` in the private env file before starting the service.

By default, DbGate listens on `127.0.0.1:3000` on the VPS. This avoids exposing a database administration UI directly to the public internet.

This module can preconfigure project database connections with:

```dotenv
DBGATE_POSTGRES_URL=postgresql://project_user:project_user_password@postgresql:5432/project_db
DBGATE_MONGO_URL=mongodb://project_user:project_user_password@mongodb:27017/project_db?authSource=project_db
```

Use the Docker network aliases `postgresql` and `mongodb` because DbGate runs on the shared `database_network`.

## Open From Your Local Machine

Use an SSH tunnel:

```bash
ssh -L 3000:127.0.0.1:3000 -p SSH_PORT deploy@YOUR_VPS_IP
```

Then open:

```text
http://127.0.0.1:3000
```

Log in with `DBGATE_LOGIN` and `DBGATE_PASSWORD` from the private env file. When `DBGATE_BASIC_AUTH=1`, the browser shows an HTTP Basic Auth prompt.

If browser access must be shared, put DbGate behind an authenticated HTTPS reverse proxy or VPN; do not bind this administration UI directly to a public interface.

## Add A PostgreSQL Connection

In DbGate, add a PostgreSQL connection with:

```text
engine: PostgreSQL
server: postgresql
port: 5432
database: project_db
user: project_user
password: project_user_password
```

Use `postgresql` as the host when PostgreSQL is attached to the shared `database_network`. Prefer a project-specific database user instead of the PostgreSQL admin user.

## Add A MongoDB Connection

In DbGate, add a MongoDB connection with a URI:

```text
mongodb://project_user:project_user_password@mongodb:27017/project_db?authSource=project_db
```

For admin maintenance, use the MongoDB root user from the private MongoDB env file:

```text
mongodb://mongo_admin:change-this-mongo-root-password@mongodb:27017/admin?authSource=admin
```

Use `mongodb` as the host when MongoDB is attached to the shared `database_network`.

## Operations

Run these commands from `database/dbgate`.

```bash
export DBGATE_ENV_FILE="$HOME/.config/vps-setup/database/dbgate.env"
docker compose --env-file "$DBGATE_ENV_FILE" ps
docker compose --env-file "$DBGATE_ENV_FILE" logs -f
docker compose --env-file "$DBGATE_ENV_FILE" restart
docker compose --env-file "$DBGATE_ENV_FILE" down
```

`docker compose down` keeps the named volume by default. DbGate settings are stored in the `dbgate_data` Docker volume unless you change `DBGATE_VOLUME_NAME`.

## Security Notes

- Keep `DBGATE_BIND_IP=127.0.0.1` unless DbGate is behind a properly secured reverse proxy.
- Use a strong `DBGATE_PASSWORD`.
- Keep `DBGATE_BASIC_AUTH=1` as a second layer even when using a tunnel or authenticated reverse proxy.
- Do not expose DbGate directly to the public internet.
- Prefer project-specific database users when browsing application databases.
- Keep the real DbGate env file outside this repository, for example at `$HOME/.config/vps-setup/database/dbgate.env`.
