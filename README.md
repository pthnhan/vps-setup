# VPS Setup Toolkit

## Setup Order

1. [Prepare Ubuntu, finalize SSH, reboot, and configure local SSH](1st-setup/README.md).
2. [Install a database](database/README.md).
3. Create a database user for each project, then connect the application.
4. Install a database UI if needed.

| Module | Guide |
| --- | --- |
| PostgreSQL | [Install and manage](database/postgresql/README.md) |
| MongoDB | [Install and manage](database/mongodb/README.md) |
| DbGate | [PostgreSQL and MongoDB UI](database/dbgate/README.md) |
| pgAdmin | [PostgreSQL UI](database/pgadmin/README.md) |
| mongo-express | [Private MongoDB maintenance UI](database/mongo-express/README.md) |

<details>
<summary>Repository checks — run locally</summary>

```bash
bash 1st-setup/test-setup.sh
```

With Docker Compose installed:

```bash
for module in database/*/; do
  docker compose -f "$module/docker-compose.yml" --env-file "$module/.env.example" config --quiet || break
done
```

</details>
