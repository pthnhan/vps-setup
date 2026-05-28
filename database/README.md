# Database Modules

This folder is a catalog of standalone database installers and database UI tools. Each module has its own Docker Compose file, environment example, and service-specific guide.

Database service modules:

- [PostgreSQL](postgresql/README.md)
- [MongoDB](mongodb/README.md)

Database UI modules:

- [DbGate](dbgate/README.md): recommended general-purpose UI for PostgreSQL and MongoDB.
- [pgAdmin](pgadmin/README.md): PostgreSQL-focused administration UI.
- [mongo-express](mongo-express/README.md): MongoDB-only UI for private development or short-lived maintenance.

## Install Once, Create Per-Project Databases

On a VPS, you usually install each database service one time. After that, every application project should get its own database, user, password, and connection string.

This keeps projects isolated:

- Project A cannot accidentally read or modify Project B data.
- Credentials can be rotated per project.
- Backups and restores can target one project database.
- A new app only needs a new database/user, not another database server.


## Private Env Files

Do not keep real `.env` files under `database/`. Store service env files outside the repository and pass them to Compose with `--env-file`.

Recommended paths:

```text
$HOME/.config/vps-setup/database/postgresql.env
$HOME/.config/vps-setup/database/mongodb.env
$HOME/.config/vps-setup/database/dbgate.env
$HOME/.config/vps-setup/database/pgadmin.env
$HOME/.config/vps-setup/database/mongo-express.env
```

Use the application repository or a secret manager for application credentials. Use the private `vps-setup` env files for VPS service admin credentials, bind addresses, ports, and UI passwords.

## Basic Service Workflow

Choose a database module and start it:

```bash
cd /home/pthnhan/workspace/vps-setup
export VPS_SETUP_SECRETS="$HOME/.config/vps-setup"
mkdir -p "$VPS_SETUP_SECRETS/database"
cp database/postgresql/.env.example "$VPS_SETUP_SECRETS/database/postgresql.env"
chmod 600 "$VPS_SETUP_SECRETS/database/postgresql.env"
nano "$VPS_SETUP_SECRETS/database/postgresql.env"

cd database/postgresql
docker network inspect database_network >/dev/null 2>&1 || docker network create database_network
docker compose --env-file "$VPS_SETUP_SECRETS/database/postgresql.env" up -d
docker compose --env-file "$VPS_SETUP_SECRETS/database/postgresql.env" ps
```

Common commands inside any database module:

```bash
export SERVICE_ENV_FILE="$HOME/.config/vps-setup/database/postgresql.env"
docker compose --env-file "$SERVICE_ENV_FILE" ps
docker compose --env-file "$SERVICE_ENV_FILE" logs -f
docker compose --env-file "$SERVICE_ENV_FILE" restart
docker compose --env-file "$SERVICE_ENV_FILE" down
```

`docker compose down` stops the service but keeps named volumes. Data stays available when you start the service again.

## Choosing A Database UI

Use one UI module at a time unless you have a specific reason to run multiple tools.

| UI | Best for | Default URL through SSH tunnel | Notes |
| --- | --- | --- | --- |
| DbGate | PostgreSQL and MongoDB in one web UI | `http://127.0.0.1:3000` | Recommended default for this repository. |
| pgAdmin | PostgreSQL-specific administration | `http://127.0.0.1:5050` | Useful for deeper PostgreSQL workflows. |
| mongo-express | MongoDB-only private development | `http://127.0.0.1:8081` | Deprecated official image; do not expose publicly. |

Start the database service first, then start the UI module. All UI modules join the shared `database_network`, so they can reach PostgreSQL at `postgresql:5432` and MongoDB at `mongodb:27017`.

Example:

```bash
cd /home/pthnhan/workspace/vps-setup
export VPS_SETUP_SECRETS="$HOME/.config/vps-setup"
mkdir -p "$VPS_SETUP_SECRETS/database"
cp database/dbgate/.env.example "$VPS_SETUP_SECRETS/database/dbgate.env"
chmod 600 "$VPS_SETUP_SECRETS/database/dbgate.env"
nano "$VPS_SETUP_SECRETS/database/dbgate.env"

cd database/dbgate
docker network inspect database_network >/dev/null 2>&1 || docker network create database_network
docker compose --env-file "$VPS_SETUP_SECRETS/database/dbgate.env" up -d
docker compose --env-file "$VPS_SETUP_SECRETS/database/dbgate.env" ps
```

By default, the UI modules bind to `127.0.0.1` on the VPS. Access them from your local machine with an SSH tunnel, or put them behind a properly secured HTTPS reverse proxy.

## Connecting From Projects

There are two common connection styles.

### Same VPS, App Runs In Docker

Use the shared Docker network created during database setup. Add the same external network to your app's `docker-compose.yml`.

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

Then use the database network alias as the host:

```text
postgresql://project_user:project_password@postgresql:5432/project_db
mongodb://project_user:project_password@mongodb:27017/project_db?authSource=project_db
```

### App Runs Outside Docker

Connect through the VPS hostname or IP and the exposed port:

```text
postgresql://project_user:project_password@VPS_HOST:5432/project_db
mongodb://project_user:project_password@VPS_HOST:27017/project_db?authSource=project_db
```

By default, the example modules bind database ports to `127.0.0.1`, which only accepts local connections on the VPS. If an outside server must connect directly, set the bind IP to `0.0.0.0`, open the firewall only for trusted source IPs, and use strong passwords.

## PostgreSQL: Create A Project Database

Enter the PostgreSQL module:

```bash
cd database/postgresql
docker compose --env-file "$VPS_SETUP_SECRETS/database/postgresql.env" exec postgres psql -U postgres
```

Create a database and user for a project:

```sql
CREATE USER project_user WITH PASSWORD 'change_this_project_password';
CREATE DATABASE project_db OWNER project_user;
GRANT ALL PRIVILEGES ON DATABASE project_db TO project_user;
\q
```

Connection string examples:

```text
DATABASE_URL=postgresql://project_user:change_this_project_password@VPS_HOST:5432/project_db
DATABASE_URL=postgresql://project_user:change_this_project_password@postgresql:5432/project_db
```

Use `VPS_HOST` for host connections and `postgresql` for apps attached to the shared Docker network.

## MongoDB: Create A Project Database

Enter the MongoDB module:

```bash
cd database/mongodb
docker compose --env-file "$VPS_SETUP_SECRETS/database/mongodb.env" exec mongodb mongo -u mongo_admin -p 'change-this-mongo-root-password' --authenticationDatabase admin
```

Create a database user for a project:

```javascript
use project_db
db.createUser({
  user: "project_user",
  pwd: "change_this_project_password",
  roles: [{ role: "readWrite", db: "project_db" }]
})
```

Connection string examples:

```text
MONGODB_URI=mongodb://project_user:change_this_project_password@VPS_HOST:27017/project_db?authSource=project_db
MONGODB_URI=mongodb://project_user:change_this_project_password@mongodb:27017/project_db?authSource=project_db
```

Use `VPS_HOST` for host connections and `mongodb` for apps attached to the shared Docker network.

## Security Notes

- Change every password in the private env file before starting a database.
- Prefer binding database ports to `127.0.0.1`.
- Prefer binding database UI ports to `127.0.0.1`.
- If public database access is unavoidable, restrict the firewall to known IP addresses.
- Do not expose database UIs directly to the public internet.
- Do not put real service env files inside this repository. Keep them in a private path such as `$HOME/.config/vps-setup/database`.
- Give each project its own database user with only the privileges it needs.
