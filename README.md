# VPS Setup Toolkit

A small set of guides and Docker Compose modules for preparing a new Ubuntu VPS and running shared services.

## Start Here

For a completely new VPS, follow [1st-setup/README.md](1st-setup/README.md). Its setup script updates Ubuntu, creates the administrative user, installs the SSH key, configures SSH/UFW/Fail2ban, adds swap, and installs Docker.

Do not clone this repository onto the VPS during the initial setup. Clone it only after the `1st-setup` guide says the server is ready.

## Repository Layout

```text
1st-setup/
  README.md
  setup.sh
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

## After First Setup

When the first-setup script has been finalized and the new SSH login works, clone the repository as the administrative user:

```bash
git clone https://github.com/pthnhan/vps-setup.git "$HOME/vps-setup"
cd "$HOME/vps-setup"
```

Then continue with the service module you need.
