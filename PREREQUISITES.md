# Prerequisites - Database Design workshop

**Send this to participants at least 2 days before.** Setup takes 10 minutes, mostly waiting for downloads.
You need no database knowledge beyond basic SQL (`SELECT`, `JOIN`, `INSERT`). You do **not** need to install PostgreSQL or MongoDB.

## What you need

| | Required | Notes |
|---|---|---|
| Laptop | 8 GB RAM, ~3 GB free disk | macOS, Linux or Windows 10/11 |
| **Docker** | Docker Desktop 4.x (or Docker Engine 24+ with the Compose plugin) | `docker compose version` must work. Colima / Rancher Desktop / Podman-with-docker-compose also work. |
| Git | any | or download the repository as a ZIP |
| Text editor | any | VS Code recommended (the SQL files are plain text) |
| Terminal | any | Windows: use **WSL2** or Git Bash |

Optional: a GUI client (DBeaver, TablePlus, DataGrip, Compass). Not required - the repository can start Adminer and
mongo-express in your browser instead (see below).

## Setup (3 commands)

```bash
git clone <repository-url> database-design && cd database-design
docker compose pull          # downloads ~1 GB once - do this on a good connection, NOT at the venue
./scripts/check-setup.sh     # starts the databases and verifies everything works
```

When the script ends with **"All good - you are ready for the workshop"** you are done.
(Without bash: `docker compose up -d --wait`, then `docker compose exec postgres psql -U workshop -d saas -c "select 1"` and `docker compose exec mongo mongosh --eval "db.version()"`.)

## Cheat sheet you will use during the workshop

```bash
docker compose up -d                                   # start (data is kept between restarts)
docker compose exec postgres psql -U workshop -d saas  # PostgreSQL shell  (\dt  \d table  \q)
docker compose exec mongo mongosh boardly              # MongoDB shell
docker compose exec -T postgres psql -U workshop -d saas -f /workshop/<path>.sql   # run a file from the repo
docker compose --profile ui up -d                      # optional web UIs: Adminer http://localhost:8080 , mongo-express http://localhost:8081
docker compose down -v                                 # stop AND delete all data (fresh start)
```

Adminer login: system *PostgreSQL*, server `postgres`, user `workshop`, password `workshop`, database `saas`.
External GUI clients: `localhost:5432` (user/password `workshop`/`workshop`, db `saas`) and `mongodb://localhost:27017`.

## Troubleshooting

| Problem | Fix |
|---|---|
| `port is already allocated` (5432 / 27017) | You have a local PostgreSQL/MongoDB running. Stop it, or change the left side of the port mapping in `docker-compose.yml` (e.g. `"5433:5432"`). |
| `Cannot connect to the Docker daemon` | Start Docker Desktop and wait until it says "running". |
| Apple-silicon / ARM laptop | Works out of the box (official multi-arch images). |
| Docker is slow / out of memory | Docker Desktop -> Settings -> Resources: give it at least 4 GB RAM. |
| Corporate laptop blocks Docker Hub | Tell the instructor in advance - we can provide the images on a USB stick (`docker load`) or a shared server. |
