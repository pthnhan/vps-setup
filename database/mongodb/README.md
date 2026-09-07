# MongoDB

Follow [database prerequisites](../README.md) first.

## 1. Configure — VPS

On an x86_64 VPS, verify AVX support before starting MongoDB 8.0. Stop if AVX is missing:

```bash
lscpu | grep -qw avx && echo 'AVX supported' || echo 'AVX missing: use a compatible VPS'
```

```bash
cd "$HOME/vps-setup"
export VPS_SETUP_SECRETS="$HOME/.config/vps-setup"
export MONGODB_ENV_FILE="$VPS_SETUP_SECRETS/database/mongodb.env"
umask 077
mkdir -p "$VPS_SETUP_SECRETS/database"
test -e "$MONGODB_ENV_FILE" || cp database/mongodb/.env.example "$MONGODB_ENV_FILE"
chmod 600 "$MONGODB_ENV_FILE"
nano "$MONGODB_ENV_FILE"
```

Set `MONGO_INITDB_ROOT_PASSWORD` to a new password. Keep the bind IP at `127.0.0.1`.

## 2. Start — VPS

```bash
cd database/mongodb
docker network inspect database_network >/dev/null 2>&1 || docker network create database_network
docker compose --env-file "$MONGODB_ENV_FILE" up -d --wait
docker compose --env-file "$MONGODB_ENV_FILE" ps
```

## 3. Create A Project User — VPS

Use your configured admin username if you changed `mongo_admin`.

```bash
docker compose --env-file "$MONGODB_ENV_FILE" exec mongodb mongosh -u mongo_admin -p --authenticationDatabase admin
```

Replace the project name, username, and password:

```javascript
use project_db
db.createUser({
  user: "project_user",
  pwd: passwordPrompt(),
  roles: [{ role: "readWrite", db: "project_db" }]
})
exit
```

## 4. Connect

**App on the VPS:**

```text
mongodb://project_user:PROJECT_PASSWORD@127.0.0.1:27017/project_db?authSource=project_db
```

**App in Docker:** replace `127.0.0.1` with `mongodb` and attach [database_network](../README.md#3-connect-an-application).

**Local workstation:** keep this tunnel running, then use the URI above:

```bash
ssh -o ExitOnForwardFailure=yes -N -L 27017:127.0.0.1:27017 vps
```

## 5. Back Up And Restore — VPS

Run from `~/vps-setup/database/mongodb`. In a new shell, set the env path first:

```bash
export MONGODB_ENV_FILE="$HOME/.config/vps-setup/database/mongodb.env"
```

Back up:

```bash
umask 077
export BACKUP_DIR="$HOME/.local/state/vps-setup/backups"
mkdir -p "$BACKUP_DIR"
backup_tmp="$(mktemp "$BACKUP_DIR/project_db.archive.XXXXXX")"
docker compose --env-file "$MONGODB_ENV_FILE" exec -T mongodb sh -c '
  exec mongodump --username "$MONGO_INITDB_ROOT_USERNAME" \
    --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin \
    --db project_db --archive
' > "$backup_tmp" && mv "$backup_tmp" "$BACKUP_DIR/project_db.archive"
```

After success, copy the backup off the VPS. On failure, inspect the error and temporary file before retrying.

Restore into an empty target database; create the project user separately:

```bash
export BACKUP_DIR="$HOME/.local/state/vps-setup/backups"
docker compose --env-file "$MONGODB_ENV_FILE" exec -T mongodb sh -c '
  exec mongorestore --username "$MONGO_INITDB_ROOT_USERNAME" \
    --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin \
    --archive --nsInclude "project_db.*" --stopOnError
' < "$BACKUP_DIR/project_db.archive"
```

## 6. Update — VPS

Back up first. Keep the current major image tag and run:

```bash
docker compose --env-file "$MONGODB_ENV_FILE" pull
docker compose --env-file "$MONGODB_ENV_FILE" up -d --wait
docker compose --env-file "$MONGODB_ENV_FILE" ps
```

For a major upgrade, follow [MongoDB version-specific upgrade instructions](https://www.mongodb.com/docs/manual/release-notes/8.0-upgrade/). Test the migration and restore before replacing production data.

See [service operations](../README.md#4-manage-a-service--vps) for logs, restarts, and stopping.
