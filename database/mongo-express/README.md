# mongo-express

Follow [database prerequisites](../README.md) first.

## 1. Configure — VPS

Use only for private maintenance; the official image is deprecated. Start [MongoDB](../mongodb/README.md) first.

```bash
cd "$HOME/vps-setup"
export VPS_SETUP_SECRETS="$HOME/.config/vps-setup"
export MONGO_EXPRESS_ENV_FILE="$VPS_SETUP_SECRETS/database/mongo-express.env"
umask 077
mkdir -p "$VPS_SETUP_SECRETS/database"
test -e "$MONGO_EXPRESS_ENV_FILE" || cp database/mongo-express/.env.example "$MONGO_EXPRESS_ENV_FILE"
chmod 600 "$MONGO_EXPRESS_ENV_FILE"
nano "$MONGO_EXPRESS_ENV_FILE"
```

Set these values before starting:

- `MONGO_EXPRESS_BASICAUTH_PASSWORD`: new UI password.
- `MONGO_EXPRESS_MONGODB_ADMINUSERNAME` / `MONGO_EXPRESS_MONGODB_ADMINPASSWORD`: MongoDB admin credentials.
- `MONGO_EXPRESS_SITE_COOKIESECRET` / `MONGO_EXPRESS_SITE_SESSIONSECRET`: separate random secrets.

Keep `MONGO_EXPRESS_BIND_IP=127.0.0.1`. Use URI-safe MongoDB credentials, such as hexadecimal passwords.

## 2. Start — VPS

```bash
cd database/mongo-express
docker network inspect database_network >/dev/null 2>&1 || docker network create database_network
docker compose --env-file "$MONGO_EXPRESS_ENV_FILE" up -d
docker compose --env-file "$MONGO_EXPRESS_ENV_FILE" ps
```

## 3. Open — Local

Keep this tunnel running:

```bash
ssh -o ExitOnForwardFailure=yes -N -L 8081:127.0.0.1:8081 vps
```

Open `http://127.0.0.1:8081` and log in with `MONGO_EXPRESS_BASICAUTH_USERNAME` / `MONGO_EXPRESS_BASICAUTH_PASSWORD`.

Use the configured admin connection only for maintenance. Close the tunnel and stop the UI when finished.

See [service operations](../README.md#4-manage-a-service--vps) for logs, restarts, and stopping.
