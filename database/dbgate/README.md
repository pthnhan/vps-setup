# DbGate

Follow [database prerequisites](../README.md) first.

## 1. Configure — VPS

Start [PostgreSQL](../postgresql/README.md) and/or [MongoDB](../mongodb/README.md) first.

```bash
cd "$HOME/vps-setup"
export VPS_SETUP_SECRETS="$HOME/.config/vps-setup"
export DBGATE_ENV_FILE="$VPS_SETUP_SECRETS/database/dbgate.env"
umask 077
mkdir -p "$VPS_SETUP_SECRETS/database"
test -e "$DBGATE_ENV_FILE" || cp database/dbgate/.env.example "$DBGATE_ENV_FILE"
chmod 600 "$DBGATE_ENV_FILE"
nano "$DBGATE_ENV_FILE"
```

Set `DBGATE_PASSWORD` to a new password. Keep the bind IP at `127.0.0.1`. Keep `DBGATE_BASIC_AUTH=1` and leave `DBGATE_CONNECTIONS` empty to add connections in the UI.

## 2. Start — VPS

```bash
cd database/dbgate
docker network inspect database_network >/dev/null 2>&1 || docker network create database_network
docker compose --env-file "$DBGATE_ENV_FILE" up -d
docker compose --env-file "$DBGATE_ENV_FILE" ps
```

## 3. Open — Local

Keep this tunnel running:

```bash
ssh -o ExitOnForwardFailure=yes -N -L 3000:127.0.0.1:3000 vps
```

Open `http://127.0.0.1:3000` and log in with `DBGATE_LOGIN` / `DBGATE_PASSWORD`.

## 4. Add A Connection

Use the project's database credentials:

| Field | PostgreSQL | MongoDB |
| --- | --- | --- |
| Engine | PostgreSQL | MongoDB |
| Server | `postgresql` | `mongodb` |
| Port | `5432` | `27017` |
| Database | `project_db` | `project_db` |
| User | `project_user` | `project_user` |

For MongoDB, use this URI:

```text
mongodb://project_user:PROJECT_PASSWORD@mongodb:27017/project_db?authSource=project_db
```

For env-based connections, set `DBGATE_CONNECTIONS` to `crypto_postgres`, `crypto_mongo`, or both comma-separated, and fill the corresponding `DBGATE_POSTGRES_URL` / `DBGATE_MONGO_URL`.

See [service operations](../README.md#4-manage-a-service--vps) for logs, restarts, and stopping.
