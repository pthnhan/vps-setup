# MongoDB

This module runs one MongoDB service for the VPS. Install it once, then create a separate database user for each application project.

MongoDB creates a database when data is first written to it. The important setup step is creating a project-specific user with access only to that project database.

## Start MongoDB

Run these commands from the repository root.

This module uses `mongo:4.4` so it can run on VPS CPUs without AVX support. MongoDB
5.0 and newer require AVX-capable CPUs.

```bash
cd /home/pthnhan/workspace/vps-setup
export VPS_SETUP_SECRETS="$HOME/.config/vps-setup"
export MONGODB_ENV_FILE="$VPS_SETUP_SECRETS/database/mongodb.env"
mkdir -p "$VPS_SETUP_SECRETS/database"
cp database/mongodb/.env.example "$MONGODB_ENV_FILE"
chmod 600 "$MONGODB_ENV_FILE"
nano "$MONGODB_ENV_FILE"

cd database/mongodb
docker network inspect database_network >/dev/null 2>&1 || docker network create database_network
docker compose --env-file "$MONGODB_ENV_FILE" up -d
docker compose --env-file "$MONGODB_ENV_FILE" ps
```

Change `MONGO_INITDB_ROOT_PASSWORD` before starting the service.

By default, MongoDB listens on `127.0.0.1:27017` on the VPS. This is safer than exposing it publicly.

## Create A Database User For A New Project

Open `mongo` as the MongoDB root user from the private env file:

```bash
export MONGODB_ENV_FILE="$HOME/.config/vps-setup/database/mongodb.env"
docker compose --env-file "$MONGODB_ENV_FILE" exec mongodb mongo -u mongo_admin -p 'change-this-mongo-root-password' --authenticationDatabase admin
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

For an app connecting through the VPS host or IP:

```text
MONGODB_URI=mongodb://project_user:change_this_project_password@VPS_HOST:27017/project_db?authSource=project_db
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
mkdir -p backups
docker compose --env-file "$MONGODB_ENV_FILE" exec -T mongodb mongodump \
  --username mongo_admin \
  --password 'change-this-mongo-root-password' \
  --authenticationDatabase admin \
  --db project_db \
  --archive > backups/project_db.archive
```

Restore a backup:

```bash
docker compose --env-file "$MONGODB_ENV_FILE" exec -T mongodb mongorestore \
  --username mongo_admin \
  --password 'change-this-mongo-root-password' \
  --authenticationDatabase admin \
  --archive \
  --nsInclude 'project_db.*' < backups/project_db.archive
```

For larger production databases, use a scheduled backup job and copy backup files off the VPS.

## Upgrade Notes

1. Back up every important database.
2. Read the MongoDB Docker image release notes for the target major version.
3. Update the image tag in `docker-compose.yml`.
4. Run `docker compose pull`.
5. Restart with `docker compose --env-file "$MONGODB_ENV_FILE" up -d`.

Major MongoDB upgrades can require stepping through intermediate versions. Do not change major versions casually on a production database.

## Security Notes

- Keep `MONGO_BIND_IP=127.0.0.1` unless remote access is required.
- If remote access is required, restrict the firewall to trusted source IPs.
- Use a unique database user and strong password for each project.
- Do not reuse the root password as an application password.
- Keep the real MongoDB env file outside this repository, for example at `$HOME/.config/vps-setup/database/mongodb.env`.
