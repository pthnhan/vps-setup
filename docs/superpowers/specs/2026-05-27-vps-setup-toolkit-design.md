# VPS Setup Toolkit Design

## Goal

Initialize this repository as a practical toolkit for setting up a new VPS and installing reusable server tools. The first supported tool category is databases, with PostgreSQL and MongoDB as examples.

The repository should help users install only what they need. Each installable service should be isolated so future additions can be added without coupling unrelated tools.

## Repository Shape

```text
README.md
database/
  README.md
  postgresql/
    docker-compose.yml
    .env.example
    README.md
  mongodb/
    docker-compose.yml
    .env.example
    README.md
```

## Root Documentation

The root `README.md` presents the repository as a VPS setup toolkit. It should include:

- A new VPS setup checklist covering SSH hardening, system updates, firewall basics, Docker and Docker Compose installation, swap, timezone, and common tools.
- Repository layout and usage model.
- Instructions that each installable tool lives in its own folder.
- A pointer to the database module documentation.

The root guide should be clear enough for a user setting up a fresh VPS, while keeping detailed database workflows inside `database/README.md` and each database module.

## Database Module Design

The `database/` folder is a catalog of independent database installers. PostgreSQL and MongoDB are the first examples.

Each database folder owns:

- `docker-compose.yml` for that service only.
- `.env.example` with safe placeholder configuration.
- `README.md` with service-specific start, stop, connection, backup, and maintenance notes.

The modules should use named Docker volumes for persistence, private env files outside the repository for credentials and ports, and `restart: unless-stopped` for normal VPS operation.

## Per-Project Database Usage

The database guide must explicitly explain that users usually install a database service once on the VPS, then create separate databases, users, credentials, and connection strings for each application project.

For PostgreSQL, the docs should show how to:

- Enter the PostgreSQL container.
- Create a new database for a project.
- Create a dedicated user for that project.
- Grant privileges.
- Build a connection string such as `postgresql://project_user:password@VPS_HOST:5432/project_db`.

For MongoDB, the docs should show how to:

- Enter the MongoDB container shell.
- Switch to a project database.
- Create a dedicated user for that project database.
- Build a connection string such as `mongodb://project_user:password@VPS_HOST:27017/project_db?authSource=project_db`.

The docs should also note that applications can connect through the public VPS hostname/IP and exposed port, or through a shared Docker network if the app runs on the same VPS with Docker.

## Error Handling And Operations

The documentation should include common operational commands:

- Check service status with `docker compose --env-file "$SERVICE_ENV_FILE" ps`.
- View logs with `docker compose --env-file "$SERVICE_ENV_FILE" logs -f`.
- Stop a service with `docker compose --env-file "$SERVICE_ENV_FILE" down`.
- Restart a service with `docker compose --env-file "$SERVICE_ENV_FILE" restart`.
- Preserve data by keeping Docker named volumes.

Service-specific READMEs should include basic backup and restore examples suitable for small VPS deployments.

## Testing And Verification

Since this repository is documentation and Docker Compose configuration, verification should focus on static checks:

- Confirm expected files exist.
- Run `docker compose config` in each database module if Docker Compose is available.
- Review documentation for placeholders, contradictions, and missing project-level connection guidance.

## Scope

In scope:

- Initialize root VPS setup documentation.
- Add the database catalog folder.
- Add separate PostgreSQL and MongoDB Docker Compose examples.
- Add clear project-level database connection and creation guidance.

Out of scope for this initial version:

- Automated installer scripts.
- Reverse proxy setup.
- SSL certificate automation.
- Monitoring stacks.
- Additional databases beyond PostgreSQL and MongoDB.
