# Database Design - 4-hour workshop

Design robust, scalable and maintainable database systems for modern applications: real-world schema design,
performance, and how database decisions shape your APIs and architecture.

**Audience:** backend developers, fullstack engineers, DevOps engineers working with relational or hybrid systems.
**Format:** 4 h including breaks - short theory blocks with live demos, two hands-on exercises
(PostgreSQL, then MongoDB), both built around one running example: **Boardly**, a multi-tenant B2B SaaS.

## Timetable (240 min)

| Time | Min | Block | Type |
|---|---|---|---|
| 0:00 | 10 | Welcome, goals, setup check (`check-setup.sh`) | |
| 0:10 | 18 | 1. Relational modeling fundamentals in real systems | talk + demo |
| 0:28 | 18 | 2. Normalization vs denormalization trade-offs | talk + [demo 1](demos/01-normalization.sql) |
| 0:46 | 5 | ☕ Break | |
| 0:51 | 18 | 3. Designing schemas for APIs and business domains | talk |
| 1:09 | 23 | 4. Indexing strategies and query optimization | talk + [demo 2](demos/02-indexing.sql) |
| 1:32 | 18 | 5. Transactions, locking and consistency models | talk + [demo 3](demos/03-transactions.sql) |
| 1:50 | 20 | 🍽 **Lunch / main break** | |
| 2:10 | 15 | 6. Designing multi-tenant and SaaS-ready schemas | talk + [demo 4](demos/04-multitenancy-rls.sql) |
| 2:25 | 35 | 🛠 **Exercise 1 - SaaS schema in PostgreSQL** (design, index lab, API alignment, debrief) | [hands-on](exercises/01-postgres/README.md) |
| 3:00 | 5 | ☕ Break | |
| 3:05 | 15 | 7. PostgreSQL vs NoSQL: when to use what | talk |
| 3:20 | 25 | 🛠 **Exercise 2 - Flexible data in MongoDB** (feed, custom fields, comments, debrief) | [hands-on](exercises/02-mongo/README.md) |
| 3:45 | 10 | 8. Common database design mistakes in production | game + [demo 5](demos/05-mistakes.sql) |
| 3:55 | 5 | Wrap-up: checklist, further reading, feedback | |

Minute-by-minute facilitator notes, talking points, demo scripts and timing fallbacks:
**[docs/facilitator-guide.md](docs/facilitator-guide.md)**.

## Prerequisites for participants

Only **Docker** (with Compose) and a terminal - no local database installs.
Full instructions to send ahead of time: **[PREREQUISITES.md](PREREQUISITES.md)**.

```bash
docker compose pull && ./scripts/check-setup.sh
```

## Repository layout

```
docker-compose.yml          PostgreSQL 17 + MongoDB 8 (+ optional Adminer / mongo-express with --profile ui)
PREREQUISITES.md            send to participants 2 days before
scripts/check-setup.sh      "is my laptop ready?" check
docs/facilitator-guide.md   instructor handbook
demos/                      5 runnable instructor demos (SQL)
exercises/01-postgres/      README, starter.sql, lint.sql, lab-seed.sql, solution/
exercises/02-mongo/         README, seed.js, helpers.js, solution/
```

Everything under `/workshop` inside the containers is this repository (read-only), which is why
`psql -f /workshop/...` works.

## Running the reference solutions (instructor smoke test, ~1 min)

```bash
docker compose up -d --wait
docker compose exec -T postgres psql -U workshop -d saas -f /workshop/exercises/01-postgres/solution/schema.sql
docker compose exec -T postgres psql -U workshop -d saas -f /workshop/exercises/01-postgres/lint.sql
docker compose exec -T postgres psql -U workshop -d saas -f /workshop/exercises/01-postgres/lab-seed.sql
docker compose exec -T postgres psql -U workshop -d saas -f /workshop/exercises/01-postgres/solution/lab-indexes.sql
docker compose exec -T mongo mongosh --quiet --file /workshop/exercises/02-mongo/seed.js
docker compose exec -T mongo mongosh --quiet --file /workshop/exercises/02-mongo/solution/solution.js
```
