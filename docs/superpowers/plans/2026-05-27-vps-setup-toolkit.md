# VPS Setup Toolkit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the initial VPS setup toolkit documentation and separate reusable PostgreSQL and MongoDB database modules.

**Architecture:** The root README explains how to prepare a new VPS and how this repository is organized. The `database/` folder acts as a catalog, and each database has its own isolated folder containing Docker Compose config, environment example, and usage guide. Per-project database creation is documented as a normal workflow after the one-time database service installation.

**Tech Stack:** Markdown, Docker Compose, PostgreSQL Docker image, MongoDB Docker image.

---

## File Structure

- Modify: `README.md` - root VPS setup guide and repository index.
- Create: `database/README.md` - shared database catalog guide and per-project usage workflow.
- Create: `database/postgresql/docker-compose.yml` - PostgreSQL service definition.
- Create: `database/postgresql/.env.example` - PostgreSQL environment template.
- Create: `database/postgresql/README.md` - PostgreSQL install, project database, connection, backup, and maintenance guide.
- Create: `database/mongodb/docker-compose.yml` - MongoDB service definition.
- Create: `database/mongodb/.env.example` - MongoDB environment template.
- Create: `database/mongodb/README.md` - MongoDB install, project database, connection, backup, and maintenance guide.

## Tasks

### Task 1: Root VPS Guide

**Files:**
- Modify: `README.md`

- [x] **Step 1: Replace the current README with a VPS setup toolkit guide**

Write a root README that includes:

- Repository purpose.
- Fresh VPS setup checklist.
- Docker installation notes.
- Repository layout.
- Instructions to install tools by copying `.env.example` to a private env file outside the repository, then using `docker compose --env-file`.
- Pointer to `database/README.md`.

- [x] **Step 2: Verify root README content**

Run: `sed -n '1,260p' README.md`

Expected: output includes `VPS Setup Toolkit`, `New VPS setup checklist`, and `database/`.

### Task 2: Shared Database Catalog Guide

**Files:**
- Create: `database/README.md`

- [x] **Step 1: Add shared database workflow documentation**

Write `database/README.md` with:

- Catalog explanation.
- One-time install versus per-project database/user setup.
- General start/stop/log commands.
- Connection options for same-VPS Docker projects and projects outside Docker.
- PostgreSQL and MongoDB examples for creating project-specific databases and users.
- Security guidance for exposing ports.

- [x] **Step 2: Verify shared database guide content**

Run: `sed -n '1,320p' database/README.md`

Expected: output includes `Install once, create per-project databases`, `PostgreSQL`, `MongoDB`, and `connection string`.

### Task 3: PostgreSQL Module

**Files:**
- Create: `database/postgresql/docker-compose.yml`
- Create: `database/postgresql/.env.example`
- Create: `database/postgresql/README.md`

- [x] **Step 1: Add PostgreSQL Compose and environment files**

Create a Compose file with:

- `postgres:16-alpine`.
- Required `POSTGRES_PASSWORD`.
- Named volume.
- Healthcheck.
- External shared Docker network named from env.
- Default port binding to `127.0.0.1`.

Create `.env.example` with concrete example values for container name, database, admin user, admin password, bind IP, port, volume, network, alias, and timezone.

- [x] **Step 2: Add PostgreSQL README**

Write a service guide with:

- Install/start commands.
- Project database and user creation commands.
- Host connection string.
- Same-VPS Docker network connection string.
- Status/log/restart/stop commands.
- Backup and restore examples.
- Upgrade and security notes.

- [x] **Step 3: Verify PostgreSQL module**

Run: `docker compose --env-file .env.example config` from `database/postgresql`.

Expected: exit code 0 and rendered Compose config.

### Task 4: MongoDB Module

**Files:**
- Create: `database/mongodb/docker-compose.yml`
- Create: `database/mongodb/.env.example`
- Create: `database/mongodb/README.md`

- [x] **Step 1: Add MongoDB Compose and environment files**

Create a Compose file with:

- `mongo:7`.
- Required root username and password.
- Data and config named volumes.
- Healthcheck using authenticated `mongosh`.
- External shared Docker network named from env.
- Default port binding to `127.0.0.1`.

Create `.env.example` with concrete example values for container name, root user, root password, bind IP, port, volumes, network, alias, and timezone.

- [x] **Step 2: Add MongoDB README**

Write a service guide with:

- Install/start commands.
- Project database and user creation commands.
- Host connection string.
- Same-VPS Docker network connection string.
- Status/log/restart/stop commands.
- Backup and restore examples.
- Upgrade and security notes.

- [x] **Step 3: Verify MongoDB module**

Run: `docker compose --env-file .env.example config` from `database/mongodb`.

Expected: exit code 0 and rendered Compose config.

### Task 5: Final Static Verification

**Files:**
- Review: all created and modified files.

- [x] **Step 1: Confirm expected files exist**

Run: `test -e README.md && test -e database/README.md && test -e database/postgresql/docker-compose.yml && test -e database/postgresql/.env.example && test -e database/postgresql/README.md && test -e database/mongodb/docker-compose.yml && test -e database/mongodb/.env.example && test -e database/mongodb/README.md`

Expected: exit code 0.

- [x] **Step 2: Search for missing per-project guidance**

Run: `rg -n "Install once|per-project|CREATE DATABASE|db.createUser|connection string|docker compose --env-file" README.md database docs/superpowers`

Expected: matches appear in the root README, database guide, service READMEs, spec, and plan.

- [x] **Step 3: Check git status**

Run: `git status --short`

Expected: created and modified files are listed; no unexpected generated files are present.
