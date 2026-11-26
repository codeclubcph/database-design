# Database Design workshop

Welcome! In four hours you will design the database of a real SaaS product, make slow queries fast, watch
concurrency bugs happen on purpose, and decide when PostgreSQL is the right tool and when it is not.

You will work on one running example, **Boardly**, a multi-tenant project-management SaaS with organizations,
users, roles, subscriptions, invoices and projects. Everything runs on your own laptop in Docker.

## Before the workshop (10 minutes)

You only need **Docker** (with Compose), Git and a terminal. No local database installs.

```bash
git clone https://github.com/codeclubcph/database-design.git database-design && cd database-design
docker compose pull          # about 1 GB: do this on a good connection, not at the venue
./scripts/check-setup.sh     # starts PostgreSQL and MongoDB and checks they work
```

When you see **"All good - you are ready for the workshop"**, you are done. Full instructions and troubleshooting
are in [PREREQUISITES.md](PREREQUISITES.md). On the morning of the workshop, run `git pull` to get the latest files.

## The day

| Time | What |
|---|---|
| 0:00 | Welcome and setup check |
| 0:10 | Relational modeling, normalization vs denormalization |
| 0:46 | Short break |
| 0:51 | Schemas for APIs, indexing and query optimization, transactions and locking |
| 1:50 | Lunch break (20 min) |
| 2:10 | Multi-tenant and SaaS schemas |
| 2:25 | **Exercise 1:** design Boardly in PostgreSQL |
| 3:00 | Short break |
| 3:05 | PostgreSQL vs NoSQL |
| 3:20 | **Exercise 2:** the flexible parts of Boardly in MongoDB |
| 3:45 | Common mistakes in production, wrap-up |

## The exercises

Work in pairs. Each exercise has its own guide with the task, a timebox and hints.

| | Guide | You will |
|---|---|---|
| Exercise 1 | [exercises/01-postgres/README.md](exercises/01-postgres/README.md) | complete a schema (roles, billing, tenants), lint it, speed up three slow queries, align it with the API |
| Exercise 2 | [exercises/02-mongo/README.md](exercises/02-mongo/README.md) | fix an activity feed, tenant-defined custom fields and comments in MongoDB |

Each exercise folder has a `solution/` directory. **Please try first** and look only when you are stuck or the
exercise is over; you learn much more that way.

## Cheat sheet

```bash
docker compose up -d                                   # start the databases (data is kept)
docker compose exec postgres psql -U workshop -d saas  # PostgreSQL shell    (\dt  \d table  \q to quit)
docker compose exec mongo mongosh boardly              # MongoDB shell       (exit to quit)
docker compose down                                    # stop (keeps your data)
docker compose down -v                                 # stop AND delete all data (fresh start)
```

Run a SQL file from this repository:

```bash
docker compose exec -T postgres psql -U workshop -d saas -f /workshop/exercises/01-postgres/starter.sql
```

Inside the containers this repository is mounted read-only at `/workshop`, so any path in the repo works after that prefix.

Prefer a graphical client? Start the optional web UIs with `docker compose --profile ui up -d`:
Adminer at <http://localhost:8080> (system PostgreSQL, server `postgres`, user `workshop`, password `workshop`,
database `saas`) and mongo-express at <http://localhost:8081>. External clients connect to `localhost:5432`
(user and password `workshop`, database `saas`) and `mongodb://localhost:27017`.

## What is in this repository

```
exercises/     the two hands-on exercises (starter files, data, guides, solutions)
demos/         the instructor's demo scripts: feel free to re-run them later
PREREQUISITES.md   setup instructions and troubleshooting
docker-compose.yml PostgreSQL 17 and MongoDB 8
```

After the workshop the repository is yours: re-run the demos, redo the exercises, and reuse the linter
(`exercises/01-postgres/lint.sql`) on your own schemas with `-v schema=your_schema_name`.
