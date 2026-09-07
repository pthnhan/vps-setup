# Install Database Services

Complete [VPS setup and the local `vps` SSH alias](../1st-setup/README.md) first. Run service commands on the VPS as the administrator.

## 1. Choose A Service

Install a database, create a project user, then add a UI if needed:

| Service | Guide | VPS listener |
| --- | --- | --- |
| PostgreSQL | [Install](postgresql/README.md) | `127.0.0.1:5432` |
| MongoDB | [Install](mongodb/README.md) | `127.0.0.1:27017` |
| DbGate | [PostgreSQL / MongoDB UI](dbgate/README.md) | `127.0.0.1:3000` |
| pgAdmin | [PostgreSQL UI](pgadmin/README.md) | `127.0.0.1:5050` |
| mongo-express | [Private maintenance UI](mongo-express/README.md) | `127.0.0.1:8081` |

## 2. Prepare Credentials

Generate a separate password for each service and project:

```bash
openssl rand -hex 32
```

- Keep service env files under `$HOME/.config/vps-setup/database/` with mode `600`.
- Replace every example password before starting a service.
- Keep bind addresses at `127.0.0.1`; access remotely through the documented SSH tunnels.
- Store application credentials in the application's secret manager or private env file.
- Use a dedicated database user per project. Keep admin credentials for maintenance.
- For passwords containing reserved URI characters, percent-encode them in connection strings. Single-quote literal `$` values in Compose env files.

## 3. Connect An Application

| Application location | PostgreSQL host | MongoDB host |
| --- | --- | --- |
| On the VPS host | `127.0.0.1:5432` | `127.0.0.1:27017` |
| Docker on `database_network` | `postgresql:5432` | `mongodb:27017` |
| Local workstation | SSH tunnel from the service guide | SSH tunnel from the service guide |

For a Docker application, add this external network to its Compose file:

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

Keep untrusted tenants on separate infrastructure. Use a private network or VPN for another application server. Do not rely on UFW alone for Docker-published public ports.

## 4. Manage A Service — VPS

Set the module name to `postgresql`, `mongodb`, `dbgate`, `pgadmin`, or `mongo-express`:

```bash
module=postgresql
cd "$HOME/vps-setup/database/$module"
export SERVICE_ENV_FILE="$HOME/.config/vps-setup/database/$module.env"
```

Run the command you need:

| Action | Command |
| --- | --- |
| Status | `docker compose --env-file "$SERVICE_ENV_FILE" ps` |
| Logs | `docker compose --env-file "$SERVICE_ENV_FILE" logs -f` |
| Apply env/config changes | `docker compose --env-file "$SERVICE_ENV_FILE" up -d` |
| Restart processes | `docker compose --env-file "$SERVICE_ENV_FILE" restart` |
| Stop and keep data | `docker compose --env-file "$SERVICE_ENV_FILE" down` |

Keep named volumes; do not use `down -v` on data you need. Back up databases before updates and copy successful backups off the VPS.

To rotate an initialized PostgreSQL, MongoDB, or pgAdmin password, change it inside the service, update dependent env files, then recreate affected containers with `up -d`.

If you customize `DATABASE_NETWORK_NAME`, create that network and use the same name in every connected module/application.
