# MongoDB

This module runs one MongoDB service for the VPS. Install it once, then create a separate database user for each application project.

MongoDB creates a database when data is first written to it. The important setup step is creating a project-specific user with access only to that project database.

## Start MongoDB

Run these commands from the repository root.

This module uses the supported `mongo:8.0` release. On `x86_64`, MongoDB 5.0 and newer require an AVX-capable CPU. Check the VPS before starting:

```bash
lscpu | grep -qw avx && echo 'AVX supported' || echo 'AVX missing: do not start MongoDB 8'
```

Do not deploy the end-of-life MongoDB 4.4 branch to work around missing AVX; choose a compatible VPS or a managed database instead.

```bash
cd /path/to/vps-setup
export VPS_SETUP_SECRETS="$HOME/.config/vps-setup"
export MONGODB_ENV_FILE="$VPS_SETUP_SECRETS/database/mongodb.env"
umask 077
mkdir -p "$VPS_SETUP_SECRETS/database"
test -e "$MONGODB_ENV_FILE" || cp database/mongodb/.env.example "$MONGODB_ENV_FILE"
chmod 600 "$MONGODB_ENV_FILE"
nano "$MONGODB_ENV_FILE"

cd database/mongodb
docker network inspect database_network >/dev/null 2>&1 || docker network create database_network
docker compose --env-file "$MONGODB_ENV_FILE" up -d
docker compose --env-file "$MONGODB_ENV_FILE" ps
```

Change `MONGO_INITDB_ROOT_PASSWORD` before starting the service.

By default, MongoDB listens on `127.0.0.1:27017` on the VPS. This is safer than exposing it publicly.

## Access From Your Local Machine

Keep `MONGO_BIND_IP=127.0.0.1` and create an SSH tunnel:

```bash
ssh -i ~/.ssh/id_ed25519_vps -o ExitOnForwardFailure=yes -N -L 27017:127.0.0.1:27017 -p SSH_PORT deploy@YOUR_VPS_IP
```

Connect your local client to `127.0.0.1:27017`. The tunnel avoids a public MongoDB listener. For a separate application server, prefer a private network or VPN.

## Create A Database User For A New Project

Open `mongosh` as the MongoDB root user. Passing `-p` without a value prompts for the password and avoids putting it in shell history:

```bash
export MONGODB_ENV_FILE="$HOME/.config/vps-setup/database/mongodb.env"
docker compose --env-file "$MONGODB_ENV_FILE" exec mongodb mongosh -u mongo_admin -p --authenticationDatabase admin
```

Create a project database user:

```javascript
use project_db
db.createUser({
  user: "project_user",
  pwd: "change_this_project_password",
  roles: [{ role: "readWrite", db: "project_db" }]
})
```

Use one unique database user per app. For example, a project named `crm-api` might use:

```javascript
use crm_api
db.createUser({
  user: "crm_api_user",
  pwd: "use_a_long_random_password",
  roles: [{ role: "readWrite", db: "crm_api" }]
})
```

## Connection Strings

For an app running directly on the VPS host:

```text
MONGODB_URI=mongodb://project_user:change_this_project_password@127.0.0.1:27017/project_db?authSource=project_db
```

For an app running in Docker on the same VPS and attached to `database_network`:

```text
MONGODB_URI=mongodb://project_user:change_this_project_password@mongodb:27017/project_db?authSource=project_db
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

Run these commands from `database/mongodb`.

```bash
export MONGODB_ENV_FILE="$HOME/.config/vps-setup/database/mongodb.env"
docker compose --env-file "$MONGODB_ENV_FILE" ps
docker compose --env-file "$MONGODB_ENV_FILE" logs -f
docker compose --env-file "$MONGODB_ENV_FILE" restart
docker compose --env-file "$MONGODB_ENV_FILE" down
```

`docker compose down` keeps the named volumes by default. MongoDB data is stored in the `mongodb_data` Docker volume unless you change `MONGO_DATA_VOLUME_NAME`.

## Backup And Restore

Create a backup for one project database:

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

On dump failure, the last successful backup remains unchanged; inspect/remove the temporary file. These commands use the container credentials without putting the literal password in shell history (privileged users can still inspect process arguments).

Restore into an empty target database and recreate its project user separately:

```bash
docker compose --env-file "$MONGODB_ENV_FILE" exec -T mongodb sh -c '
  exec mongorestore --username "$MONGO_INITDB_ROOT_USERNAME" \
    --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin \
    --archive --nsInclude "project_db.*" --stopOnError
' < "$BACKUP_DIR/project_db.archive"
```

For larger production databases, use a scheduled backup job and copy backup files off the VPS.

## Upgrade Notes

1. Back up every important database.
2. Read the MongoDB Docker image release notes for the target major version.
3. For a patch update within the current major version, keep the existing image tag. For a major upgrade, complete the database-specific migration procedure with a tested backup and a separate target volume; the pull/recreate commands below do not migrate data.
4. Run `docker compose --env-file "$MONGODB_ENV_FILE" pull`.
5. Restart with `docker compose --env-file "$MONGODB_ENV_FILE" up -d`.

Major MongoDB upgrades can require stepping through intermediate versions. Do not change major versions casually on a production database.

The previous version of this module used MongoDB 4.4. An existing 4.4 data volume cannot be upgraded directly to 8.0. Follow MongoDB's supported sequential upgrade path or dump from 4.4 and restore into a fresh 8.0 instance after testing.

## Security Notes

- Keep `MONGO_BIND_IP=127.0.0.1` unless remote access is required.
- Prefer an SSH tunnel, VPN, or private network for remote access.
- Docker ports published on `0.0.0.0` can bypass UFW; do not treat UFW as the only protection for a public database listener.
- Use a unique database user and strong password for each project.
- Do not reuse the root password as an application password.
- Keep the real MongoDB env file outside this repository, for example at `$HOME/.config/vps-setup/database/mongodb.env`.
