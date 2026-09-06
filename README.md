# VPS Setup Toolkit

A small set of guides and Docker Compose modules for preparing a new Ubuntu VPS and running shared services.

## Start Here

For a completely new VPS, open [1st-setup/README.md](1st-setup/README.md) in your browser and follow it from top to bottom. The guide starts on your local computer, creates and installs an SSH key, secures the server, and installs Docker.

Do not clone this repository onto the VPS during the initial setup. Clone it only after the `1st-setup` guide says the server is ready.

## Repository Layout

```text
1st-setup/
  README.md
database/
  README.md
  postgresql/
  mongodb/
  dbgate/
  pgadmin/
  mongo-express/
```

## Service Modules

Read [database/README.md](database/README.md) before installing a database or database UI.

Database services:

- [PostgreSQL](database/postgresql/README.md)
- [MongoDB](database/mongodb/README.md)

Database UIs:

- [DbGate](database/dbgate/README.md)
- [pgAdmin](database/pgadmin/README.md)
- [mongo-express](database/mongo-express/README.md)

Keep real credentials outside this repository under `$HOME/.config/vps-setup/`. Only `.env.example` templates belong in Git.
