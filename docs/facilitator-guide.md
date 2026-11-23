# Facilitator guide - Database Design (4 h)

The workshop has one thread: **Boardly**, a multi-tenant B2B project-management SaaS (users, organizations, roles,
permissions, subscriptions, invoices, projects). Every concept is introduced with a Boardly example, then applied
in the exercises. Participants should leave able to say *"I would model it like this, index it like that, and here is the trade-off."*

**Teaching principles:** show a failure first (anomaly, slow plan, lost update), then the fix. Ask the room to predict before you run a demo.
Keep slides to a minimum - the demos in `demos/` *are* the content.

## Before the day

- [ ] Send [PREREQUISITES.md](../PREREQUISITES.md) 2-3 days ahead; ask everyone to run `./scripts/check-setup.sh` and reply "ready" (or the output).
- [ ] Venue wifi is **not** good enough for 1 GB of image pulls. Have a USB stick with `docker save postgres:17 mongo:8 | gzip` as fallback (`docker load` on the other side).
- [ ] Run the smoke test below on your own machine the morning of the workshop. Then `docker compose down -v` for a clean start.

```bash
docker compose up -d --wait
docker compose exec -T postgres psql -U workshop -d saas -f /workshop/exercises/01-postgres/solution/schema.sql
docker compose exec -T postgres psql -U workshop -d saas -f /workshop/exercises/01-postgres/lint.sql
docker compose exec -T postgres psql -U workshop -d saas -f /workshop/exercises/01-postgres/lab-seed.sql
docker compose exec -T postgres psql -U workshop -d saas -f /workshop/exercises/01-postgres/solution/lab-indexes.sql
docker compose exec -T mongo mongosh --quiet --file /workshop/exercises/02-mongo/seed.js
docker compose exec -T mongo mongosh --quiet --file /workshop/exercises/02-mongo/solution/solution.js
```

- [ ] Instructor material lives in `docs/` (this guide) and the slide deck; participants only need the root README and `PREREQUISITES.md`.
- [ ] Prepare 8-10 slides max: agenda, 3 isolation models for multi-tenancy, isolation-level table, SQL-vs-NoSQL decision table, mistakes checklist. Content is below.
- [ ] Font size 18+ in terminal and editor. Two terminals side by side ready for demo 3.
- [ ] Group size 6-20 works. Pairs for the exercises; with more than 20, add a second helper.
- [ ] Lunch timing: the 20-minute break at 1:50 is the "middle" - tell the venue to have food ready.

## Fallbacks if you are running behind

| Situation | Cut |
|---|---|
| 10 min late at the main break | Skip demo 1 section 4-5 (materialized view, jsonb); show only the update anomaly + 3NF. |
| 10 min late before Exercise 1 | Shorten Part B to Q1 + Q2 only; do Part C verbally as a group. |
| Exercise 1 pairs are not done in 35 min | Hand out `solution/schema.sql`, spend the remaining time on *reading* it and the debrief. Part B is the more valuable half - protect it. |
| Exercise 2 is running long | Do B1 + B3 only; show B2 (attribute pattern) live. |
| Ahead of schedule | Stretch goals (RLS, audit log), or pull up `lint.sql` on a participant's schema and review it live. |

---

## 0. Welcome (0:00, 10 min)

- Goal of the day in one sentence: **"Decisions in the database are the most expensive decisions to change."** Code can be refactored on Tuesday; 500 M rows and 3 consuming services cannot.
- Introduce Boardly and draw the 6 boxes on the board: Organization - Membership - User, Role - Permission, Plan - Subscription - Invoice, Project.
- Poll: who runs PostgreSQL / MySQL / Mongo / DynamoDB in production? Who has had a production incident caused by the database?
- Everyone runs `./scripts/check-setup.sh` now. Fix stragglers during block 1 (pair them with a neighbour).

## 1. Relational modeling fundamentals in real systems (0:10, 18 min)

**Learning goal:** model entities, relationships and constraints so the database protects the data - not the application.

Key points
1. **Entities, attributes, relationships.** Model nouns first (organization, user, invoice), then relationships with cardinality: 1:N, N:M, 1:1. N:M always becomes a **join table** - and the join table usually grows its own attributes (membership has status, role, joined_at). Ask: *"Is membership an entity or just a link?"* (an entity).
2. **Keys.** Natural vs surrogate. Surrogate `bigint identity` as the default; add **natural unique constraints** (email, slug, invoice number per org) on top. UUID: random UUIDv4 hurts index locality; UUIDv7 or bigint plus an external public id. Never leak sequential ids in URLs if enumeration matters - expose slug / number / public id.
3. **Constraints are free correctness.** `NOT NULL`, `CHECK`, `UNIQUE`, `FOREIGN KEY` (+ `ON DELETE` choice), exclusion constraints, partial unique indexes. "If it must always be true, the database enforces it; the app can have bugs, there may be a second app, and someone will run a manual `UPDATE` in prod."
4. **Types matter.** `timestamptz` not `timestamp`; money as integer minor units + currency (or `numeric`), never float; `text` over `varchar(255)`; `boolean` over int flags; `CHECK` or enum for state.
5. **Naming and conventions.** Singular/plural, `snake_case`, `<table>_id` for FKs, `created_at` everywhere. Consistency beats the "right" choice.
6. **Time and history.** Soft delete vs hard delete vs history table; "who changed what" -> audit log. Soft delete breaks uniqueness - use partial unique indexes.

Demo (3 min): show `exercises/01-postgres/solution/schema.sql` top (organizations, users) - point out `slug` CHECK, `lower(email)` unique index, identity column.

Ask the room: *"A user belongs to many orgs. Where do you put `role`?"* -> on the membership, not on the user. Foreshadows the exercise.

## 2. Normalization vs denormalization trade-offs (0:28, 18 min)

**Learning goal:** normalize by default, denormalize deliberately and measurably.

Key points
1. Normal forms in plain words: **1NF** no repeating groups / lists in a column; **2NF** every attribute depends on the *whole* key; **3NF** attributes depend on the key and nothing but the key. Mnemonic: "the key, the whole key, and nothing but the key".
2. Normalization exists to prevent **anomalies**: update, insert, delete. **Run [demo 1](../demos/01-normalization.sql)** - Ann ends up in two cities.
3. **Snapshot is not denormalization.** `order_lines.unit_price_cents` copies the product price on purpose: history must not change when the catalogue does. Ask: *"Is this a violation?"*
4. **When to denormalize:** measured read bottleneck; read:write ratio high; one clear owner of the write path; a drift detector or a rebuild job. Options in order of preference: better indexes -> materialized view -> stored aggregate column (`invoices.total_cents`) -> counter table -> separate read model / search index / cache.
5. Costs: write amplification, drift, dual-write bugs. "Every redundant copy is a future bug report."
6. `jsonb` is denormalization in disguise: great for sparse, rarely-filtered attributes (plan limits), poor for core relations and anything you join/aggregate on.

Discussion (2 min): *invoice total - store or compute?* Expect both answers; guide towards "store, because invoices are immutable after issue" - then they will see it in the exercise.

## ☕ Break (0:46, 5 min)

## 3. Designing schemas for APIs and business domains (0:51, 18 min)

**Learning goal:** the schema and the API are one design; each shapes the other.

Key points
1. **Start from the use cases**, not the ER diagram: list endpoints and the 5-10 queries that matter ("access patterns"), then check that the schema answers them with index lookups. (Mongo thinking, applied to SQL.)
2. **Resource vs table.** API resources are not tables: `GET /orgs/{slug}/invoices/{number}` joins organization + invoice + items. The API should never expose internal ids, join-table names or soft-delete flags.
3. **Identifiers:** slug / number / public uuid in the API, bigint internally. Uniqueness *per tenant*: `UNIQUE (org_id, number)`.
4. **Pagination:** `OFFSET` is O(n); use **keyset pagination** `WHERE (issued_at, id) < ($1, $2) ORDER BY issued_at DESC, id DESC LIMIT 20` - and the index must match the ORDER BY. Opaque cursor in the API. Show in `exercises/01-postgres/solution/api-mapping.md`.
5. **Filtering & sorting** must be whitelisted and each combination needs an index story. A "filter by anything" endpoint is an unindexable endpoint.
6. **N+1 and over-fetching:** ORM lazy loading, GraphQL resolvers. Design endpoints that map to 1-3 queries. Use `SELECT` lists, not `SELECT *`.
7. **Idempotency & concurrency in APIs:** `Idempotency-Key` table with unique constraint; `ETag`/`version` column for optimistic locking (returns 409/412).
8. **Evolving schemas without downtime:** expand -> migrate -> contract. Add nullable column, backfill in batches, add constraint `NOT VALID` then `VALIDATE`, create indexes `CONCURRENTLY`, drop in a later release. Never rename a column in one deploy.
9. **Authorization data model** (preview for the exercise): users - memberships - roles - role_permissions - permissions; the check is *one query* of primary-key lookups.

Demo (3 min): live-write the authorization query from `solution/api-mapping.md` against `\d` of the solution schema, and `EXPLAIN` it.

## 4. Indexing strategies and query optimization (1:09, 23 min)

**Learning goal:** read an execution plan and choose the right index.

Run **[demo 2](../demos/02-indexing.sql)** (the data load takes ~15 s - start it, talk about b-trees meanwhile).

Key points
1. **What an index is:** a sorted structure (b-tree) mapping column values to row locations. Reads get faster, writes get slower, disk and RAM are consumed. Draw the tree for 30 s.
2. **Reading `EXPLAIN (ANALYZE, BUFFERS)`**: Seq Scan vs Index Scan vs Index Only Scan vs Bitmap; `rows` estimated vs actual (bad estimate = stale statistics -> `ANALYZE`); `Buffers` = pages touched; `Sort` / `Hash` nodes. Always compare estimated vs actual rows first.
3. **Composite indexes - order matters.** Equality columns first, then the sort / range column. Left-prefix rule: `(org_id, created_at)` serves `org_id = ?` but not `created_at > ?` alone. In multi-tenant systems `org_id` is almost always first.
4. **Sargability:** functions on the indexed column (`lower(email)`, `date(created_at)`, `col + 1`) defeat the index -> rewrite the predicate or use an expression index. Implicit casts too.
5. **Selectivity & partial indexes:** an index on a column with 99 % one value is useless for that value; index the rare slice. Partial indexes (`WHERE status = 'open'`, `WHERE deleted_at IS NULL`) are small and fast.
6. **Covering indexes** (`INCLUDE`) -> index-only scans; need `VACUUM` for the visibility map.
7. **Other index types, briefly:** GIN (jsonb, arrays, full-text, trigram `LIKE '%x%'`), GiST (ranges, geo, exclusion constraints), BRIN (huge append-only time-series tables), hash (rare).
8. **Foreign keys are not indexed automatically** in PostgreSQL (MySQL does). Missing FK index = slow joins and slow `DELETE` on the parent (this is what `lint.sql` section 2 finds).
9. **Query habits:** no `SELECT *`, no `OFFSET` deep paging, `EXISTS` over `IN (subquery)` for large sets, batch instead of N+1, avoid `OR` across different columns, watch `count(*)` on huge tables (it is O(n) in Postgres - estimates, counter tables).
10. **Operations:** `pg_stat_statements` finds the slow queries (top by total time, not by single run); `pg_stat_user_indexes.idx_scan = 0` finds unused indexes; `CREATE INDEX CONCURRENTLY` in production; `auto_explain` for slow plans.

Questions to ask: *"What index would make `WHERE org_id = ? AND status = 'open' ORDER BY issued_at DESC LIMIT 20` instant?"* - let them answer, then reveal in demo. (This is Q1 of the exercise: say nothing more.)

## 5. Transactions, locking and consistency models (1:32, 18 min)

**Learning goal:** know what ACID guarantees and where you must still think.

Run **[demo 3](../demos/03-transactions.sql)** with two terminals (A and B) on the projector. Predict-then-run for each scenario.

Key points
1. **ACID in one sentence each.** Atomic: all or nothing. Consistent: constraints hold at commit. Isolated: concurrent transactions don't see each other's partial work (to a degree). Durable: committed = on disk (WAL).
2. **MVCC:** readers don't block writers and vice versa; writers block writers on the same row. Long transactions = bloat and blocked vacuum; **never hold a transaction across an HTTP call**.
3. **Isolation levels** (table in the demo file): READ COMMITTED (default), REPEATABLE READ, SERIALIZABLE. Anomalies: non-repeatable read, lost update, **write skew** ("last admin" example), phantom.
4. **Lost update** (demo 3.1) - three fixes: atomic `UPDATE ... SET x = x - 1`; `SELECT ... FOR UPDATE`; optimistic `version` column.
5. **Deadlocks** (demo 3.3): lock in a consistent order; retry on `40P01`.
6. **Queues:** `FOR UPDATE SKIP LOCKED` (demo 3.4) - a good-enough job queue; Postgres as a queue until ~thousands/s.
7. **Retry is part of the contract:** `40001` (serialization failure) and `40P01` must be retried by the application. Show the pattern in 5 lines of pseudocode.
8. **Constraints are the cheapest concurrency control:** a partial unique index ("one live subscription per org") beats application-level checks - two concurrent requests, one wins.
9. **Distributed consistency, briefly:** replicas lag (read-your-writes!), CAP/PACELC in one slide, eventual consistency, sagas / outbox pattern instead of distributed transactions. Dual write problem: DB + queue -> **transactional outbox** table.
10. **Billing example:** why `change-plan` is a transaction with a row lock - cancel + create must be atomic.

## 🍽 Main break (1:50, 20 min)

Use the break to start the Postgres lab seed on the projector machine (`lab-seed.sql`) so you can show timing, and to help anyone with a broken setup.

## 6. Designing multi-tenant and SaaS-ready schemas (2:10, 15 min)

**Learning goal:** choose a tenancy model and design the schema so tenant data cannot leak or collide.

Key points
1. **Three tenancy models** (slide): shared tables + `org_id` (default; cheapest, scales to 100k tenants) / schema per tenant (moderate isolation, migration pain at scale) / database per tenant (strongest isolation, per-tenant backup/restore, highest ops cost). Hybrid: shared by default, big or regulated customers get their own database.
2. **Tenant column discipline:** `org_id` on every tenant-owned table, first column of nearly every index, in every unique constraint (`UNIQUE (org_id, number)`).
3. **Tenant-safe foreign keys:** composite FK `(role_id, org_id) -> roles (id, org_id)` makes cross-tenant references impossible. Show in [demo 4](../demos/04-multitenancy-rls.sql) section 4.
4. **Row-Level Security** as a safety net: [demo 4](../demos/04-multitenancy-rls.sql). Say the gotchas (superuser/owner bypass, pooling -> `set_config(..., true)` in a transaction, fail-closed when unset).
5. **Users vs memberships:** users are global, membership links them to tenants with a role - supports consultants working for several customers. Identity (authentication) is separate from authorization (membership + role).
6. **RBAC data model:** users - memberships - roles - role_permissions - permissions. Per-org custom roles vs global fixed roles (trade-off: flexibility vs simplicity). Permissions as stable string keys in code.
7. **Billing model:** plans (catalogue) - subscriptions (history, one live per org) - invoices - invoice_items - payments; money as integer minor units; **immutable invoices** (never edit, issue a credit note); store provider ids (Stripe customer id) for reconciliation; webhooks need an idempotency table.
8. **Noisy neighbour:** the whale tenant (the lab data has one!). Mitigations: per-tenant rate limits, `statement_timeout`, partitioning by tenant or time, move the whale to its own database. Skewed data also breaks planner assumptions.
9. **Tenant lifecycle:** onboarding (seed roles), soft delete + grace period, export (GDPR), hard delete of *all* tenant rows (this is where FK `ON DELETE CASCADE` and per-tenant DB shine), per-tenant restore (hard in shared tables!).
10. **Scale-out path:** partition by `org_id` hash or time -> read replicas -> Citus / sharding with `org_id` as the shard key. Choosing `org_id` as the leading column of everything now keeps that door open.

## 🛠 Exercise 1 (2:25, 35 min)

Hand out the link to [exercises/01-postgres/README.md](../exercises/01-postgres/README.md). Pairs. Timeboxes on the projector: **A 15 min - B 10 min - C 5 min - debrief 5 min**.

Circulating checklist - things to look for and ask about:
- Role references without the composite FK? -> "can I give a user a role from a different tenant?"
- Money as `numeric`/`float`? `numeric` is acceptable, float is not.
- `UNIQUE(number)` instead of `UNIQUE(org_id, number)`? Classic multi-tenant bug.
- Missing FK indexes -> have them run `lint.sql`.
- Part B: pairs who add an index per column instead of a composite. Ask them to compare `Buffers`.
- Pairs who finish early -> stretch goals.

Common wrong turns: forgetting `UNIQUE (id, org_id)` on roles (FK creation error - good learning moment); putting `role` on `users`; one `status` index with 99 % selectivity.

Debrief (5 min): show two different pair solutions on the projector; ask what each costs to change later. Then reveal `solution/schema.sql` and `api-mapping.md` - emphasize that it is *a* good answer. Show the before/after times from `solution/lab-indexes.sql` (e.g. ~125 ms -> 0.1 ms for Q1).

## ☕ Break (3:00, 5 min)

## 7. PostgreSQL vs NoSQL: when to use what (3:05, 15 min)

**Learning goal:** choose by access patterns, consistency needs and operational reality - not by fashion.

Key points
1. **"NoSQL" is four different things:** document (MongoDB, Firestore), key-value (Redis, DynamoDB), wide-column (Cassandra, Bigtable), graph (Neo4j); plus search (Elasticsearch/OpenSearch), time-series (TimescaleDB, InfluxDB), vector. Pick by access pattern.
2. **Decision table** (slide):

| You need... | Reach for | Why |
|---|---|---|
| Transactions across entities, constraints, ad-hoc queries, reporting | **PostgreSQL** | the default; joins and integrity |
| Semi-structured attributes next to relational data | **PostgreSQL + jsonb** | one database, GIN-indexable |
| Huge write volume, key-based access, predictable low latency at massive scale | **DynamoDB / Cassandra** | horizontal by design, but you must know the access patterns up front |
| Self-contained documents read as a unit, schema evolving fast, per-tenant shapes | **MongoDB** | document model, flexible; multi-document transactions exist but are not its sweet spot |
| Caching, sessions, rate limits, leaderboards, ephemeral locks | **Redis** | in-memory data structures |
| Full-text search, faceting, relevance | **OpenSearch / Elasticsearch** (or PG full-text first) | inverted indexes; usually a *derived* store |
| Metrics, IoT, time-series | **TimescaleDB / ClickHouse** | columnar/compressed time partitions |
| Deep relationship traversal (fraud rings, recommendations) | **Graph DB** | traversals instead of recursive joins |

3. **Polyglot persistence in practice:** the relational DB is the **system of record**; others are derived (search index, cache, analytics) or specialised (event feed). Source of truth must be explicit. Sync through the **outbox + CDC** pattern, not dual writes.
4. **The honest comparison:** PostgreSQL has jsonb, full-text, `SKIP LOCKED` queues, partitioning, extensions (PostGIS, pgvector, Timescale). *"Just use Postgres"* is right surprisingly often. NoSQL wins when scale or access pattern truly demands it - not because "schema-less is faster to start" (the schema still exists, in your code and in every document).
5. **Document modeling rules (preview of Exercise 2):** embed what you read together and what is bounded; reference what is unbounded/shared/independent; design for queries; patterns: attribute, subset, bucket, outlier. Indexes still matter (ESR rule).
6. **Consistency & trade-offs:** tunable consistency, eventual consistency, no cross-collection FKs, you own integrity. Joins ($lookup) exist but are not the strength.
7. **Cost of a second database:** another thing to back up, monitor, secure, upgrade, learn. Rule: add a store when you can name the *specific query or workload* Postgres cannot serve.

Boardly mapping to say out loud: users / billing / roles -> PostgreSQL (integrity!). Activity feed + tenant-defined fields -> MongoDB candidate. Sessions / rate limits -> Redis. Search -> derived index.

## 🛠 Exercise 2 (3:20, 25 min)

Hand out [exercises/02-mongo/README.md](../exercises/02-mongo/README.md). Everyone runs `seed.js` first (~10 s), then Part A on paper (5 min), Part B (15 min), debrief 5.

Look for:
- "Embed comments" decisions - ask for the document size number.
- One index per field instead of compound indexes -> ESR rule.
- `$elemMatch` forgotten in the attribute-pattern query (matching `k` and `v` in *different* array elements - show this bug live, it is a great teaching moment).
- Plan output: `COLLSCAN`, `SORT`, `docsExamined >> nReturned`.

Debrief answers: Mongo is the better fit for tenant-defined shapes and append-only feeds; billing stays in Postgres because it needs multi-row transactions, constraints and reporting. The tenant boundary in Mongo is *convention* (`org_id` in every query and index) - wrap data access in a repository that always injects `org_id`.

## 8. Common database design mistakes in production (3:45, 10 min)

Format: **spot-the-bug game.** Show [demo 5](../demos/05-mistakes.sql) on screen, teams call out mistakes (2 min), then reveal and run the linter on schema `bad` (1 min). Spend the remaining time on the checklist. Pick 5-6 from:

| Mistake | Consequence | Fix |
|---|---|---|
| No foreign keys "for performance" | orphans, silent corruption | declare FKs; index them |
| Missing FK indexes | slow joins and deletes | index every FK |
| `timestamp` without tz; float money | wrong times, wrong cents | `timestamptz`; integer cents / `numeric` |
| EAV / one-big-jsonb | no types, no constraints, impossible queries | real columns for core fields, jsonb for the long tail |
| Soft delete without partial unique indexes | "email already taken" by ghosts | partial unique `WHERE deleted_at IS NULL` |
| Random UUIDv4 PKs everywhere | index bloat, cache misses | bigint or UUIDv7 |
| `SELECT *`, N+1, `OFFSET` pagination | slow at scale | explicit columns, joins/batching, keyset |
| Long transactions / locks held over network calls | blocked writers, outages | short transactions, timeouts |
| Migrations that lock big tables | downtime | expand/contract, `CONCURRENTLY`, `NOT VALID` + `VALIDATE`, batch backfills |
| One giant "god" table / no tenant column | un-shardable, data leaks | model entities; `org_id` everywhere |
| Cache or search as the source of truth | data loss | DB is the source of truth; others are derived |
| No connection pooling | `too many connections` at 200 pods | PgBouncer / pool sizing |
| Backups never restored; no `statement_timeout`; app uses superuser | one bad day ends the company | restore drills, timeouts, least privilege |
| Premature NoSQL / premature microservice-per-database | distributed joins in the app | start boring; split when you can name the reason |

## Wrap-up (3:55, 5 min)

- One-slide **design checklist** (the table above condensed + "for every table: PK? tenant? FKs + indexes? constraints? types? who writes it?").
- Further reading: *Use The Index, Luke* (use-the-index-luke.com); *Designing Data-Intensive Applications* (Kleppmann); PostgreSQL docs chapters on indexes and concurrency control; MongoDB "Building with Patterns" blog series; Crunchy Data and Cybertec blogs.
- Tell them how to keep the environment: `docker compose down` keeps data; the repository is theirs to reuse.
- Feedback: three questions (one thing you'll change on Monday; one thing that was unclear; pace too fast/slow). Ask for it on paper or a shared form.

## Appendix - answers to questions you will get

- **"Why bigint identity instead of UUID?"** Smaller, faster indexes, ordered inserts; combine with a public id if the id is exposed. UUIDv7 gives ordering + global uniqueness; Postgres 18 has `uuidv7()`.
- **"Should I use an ENUM type?"** `CHECK (status IN (...))` is easier to evolve (adding a value to a native enum is fine, removing is hard). Reference tables when values carry attributes or need translations.
- **"Table partitioning?"** When one table is >100 GB or you drop data by time range. Partition key must be in the PK/unique constraints. Not a substitute for indexes.
- **"How many indexes is too many?"** When write throughput or disk becomes a problem; every index is a cost on every write. Drop unused ones (`idx_scan = 0` after a representative period).
- **"MySQL differences?"** InnoDB auto-indexes FKs, clustered primary key (random UUID PKs hurt more), no partial indexes, transactional DDL absent. The principles transfer.
- **"Is `jsonb` just a document DB?"** For many workloads, yes - and with transactions, joins and constraints on the rest. Limits: large documents are TOASTed; updates rewrite the whole value; no cross-document sharding story.
