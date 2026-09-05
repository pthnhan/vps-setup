# mongo-express

mongo-express is a MongoDB-only web UI.

The official Docker image is deprecated because of maintainer inactivity and Docker Hub lists no supported tags or architectures. Use this module only for private development or short-lived maintenance. For a better default MongoDB UI on this VPS, use [DbGate](../dbgate/README.md). For a desktop client, consider MongoDB Compass over an SSH tunnel.

## Start mongo-express

Run these commands from the repository root.

Start MongoDB first, then start mongo-express:

```bash
cd /path/to/vps-setup
export VPS_SETUP_SECRETS="$HOME/.config/vps-setup"
export MONGO_EXPRESS_ENV_FILE="$VPS_SETUP_SECRETS/database/mongo-express.env"
mkdir -p "$VPS_SETUP_SECRETS/database"
cp database/mongo-express/.env.example "$MONGO_EXPRESS_ENV_FILE"
chmod 600 "$MONGO_EXPRESS_ENV_FILE"
nano "$MONGO_EXPRESS_ENV_FILE"

cd database/mongo-express
docker network inspect database_network >/dev/null 2>&1 || docker network create database_network
docker compose --env-file "$MONGO_EXPRESS_ENV_FILE" up -d
docker compose --env-file "$MONGO_EXPRESS_ENV_FILE" ps
```

Change these values before starting the service:

- `MONGO_EXPRESS_BASICAUTH_PASSWORD`
- `MONGO_EXPRESS_MONGODB_ADMINPASSWORD`
- `MONGO_EXPRESS_SITE_COOKIESECRET`
- `MONGO_EXPRESS_SITE_SESSIONSECRET`

Set `MONGO_EXPRESS_MONGODB_ADMINPASSWORD` to the same value as `MONGO_INITDB_ROOT_PASSWORD` in the private MongoDB env file.

By default, mongo-express listens on `127.0.0.1:8081` on the VPS. This avoids exposing a database administration UI directly to the public internet.

## Open From Your Local Machine

Use an SSH tunnel:

```bash
ssh -L 8081:127.0.0.1:8081 -p SSH_PORT deploy@YOUR_VPS_IP
```

Then open:

```text
http://127.0.0.1:8081
```

Log in with `MONGO_EXPRESS_BASICAUTH_USERNAME` and `MONGO_EXPRESS_BASICAUTH_PASSWORD` from the private env file.

## Access Model

This module defaults to admin mode:

```dotenv
MONGO_EXPRESS_MONGODB_ENABLE_ADMIN=true
```

That lets mongo-express use the MongoDB root user and browse all databases. This is convenient, but broad. For routine application work, prefer a project-specific MongoDB user in DbGate or MongoDB Compass.

## Operations

Run these commands from `database/mongo-express`.

```bash
export MONGO_EXPRESS_ENV_FILE="$HOME/.config/vps-setup/database/mongo-express.env"
docker compose --env-file "$MONGO_EXPRESS_ENV_FILE" ps
docker compose --env-file "$MONGO_EXPRESS_ENV_FILE" logs -f
docker compose --env-file "$MONGO_EXPRESS_ENV_FILE" restart
docker compose --env-file "$MONGO_EXPRESS_ENV_FILE" down
```

## Security Notes

- Keep `MONGO_EXPRESS_BIND_IP=127.0.0.1`.
- Use mongo-express only privately for development or short-lived maintenance.
- Do not expose mongo-express directly to the public internet.
- Use strong basic-auth, cookie, and session secrets.
- Keep the real mongo-express env file outside this repository, for example at `$HOME/.config/vps-setup/database/mongo-express.env`.
