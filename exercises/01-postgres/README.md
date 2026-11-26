# Exercise 1 - Design the database of a SaaS product (PostgreSQL)

**Time: 35 min** (A: 15 min, B: 10 min, C: 5 min, debrief: 5 min). Work in pairs.

You are the backend team of **"Boardly"**, a B2B project-management SaaS. Customers are *organizations* (tenants).
People sign up, join one or more organizations with a role, the organization pays a monthly subscription, and
works on projects. You own the database and the REST API that sits on top of it.

> Prerequisite: `docker compose up -d` is running (see the root [README](../../README.md)).
> Open a shell: `docker compose exec postgres psql -U workshop -d saas`

## Business rules

1. A **user** has one global account (unique e-mail, case-insensitive) and can belong to **many organizations**.
2. Inside an organization a user has exactly **one role** (e.g. `owner`, `admin`, `member`, `billing`).
   Each organization manages **its own** roles. A role is a set of **permissions** such as `invoice:read`.
3. It must be **impossible at the database level** to assign a user a role from a different organization.
4. A membership is `invited`, `active` or `suspended`.
5. The product has a global catalogue of **plans** (free, pro, ...). An organization subscribes to a plan.
   The subscription is `trialing`, `active`, `past_due` or `canceled`. History is kept, but an organization
   can have **at most one live** subscription (trialing / active / past_due).
6. **Invoices** belong to an organization, have a human-readable number (`INV-2026-0001`) that is unique
   **per organization**, a status (`draft`, `open`, `paid`, `void`), line items, and money in a currency.
7. Organizations create **projects**. Active project names are unique per organization (case-insensitive);
   archived projects free their name.
8. Organizations are **soft-deleted** (`deleted_at`).

## API you must support

| # | Endpoint | Notes |
|---|----------|-------|
| 1 | `GET /orgs/{slug}/members` | with role name |
| 2 | `GET /me/orgs` | every org the current user belongs to |
| 3 | `GET /orgs/{slug}/invoices?status=open` | newest first, **keyset pagination**, page size 20 |
| 4 | `GET /orgs/{slug}/invoices/{number}` | invoice + items |
| 5 | `GET /orgs/{slug}/projects` | active only, newest first |
| 6 | `POST /orgs/{slug}/subscription/change-plan` | must be atomic |
| 7 | *Authorization check* | "does user U have permission `invoice:write` in org O?" - runs on **every request** |

Never expose internal numeric ids in URLs: the API speaks in `slug` and `number`.

---

## Part A - Design the schema (15 min)

Open [`starter.sql`](starter.sql). `organizations` and `users` are done. Complete TODO 1-6.

```bash
docker compose exec -T postgres psql -U workshop -d saas -f /workshop/exercises/01-postgres/starter.sql
```

Draw the tables on paper first (boxes and arrows, 3 minutes), then write the DDL.

**Rules of thumb for the room:** `NOT NULL` by default - `CHECK` constraints for every enum - money is integer
minor units - `timestamptz`, never `timestamp` - every foreign key gets an index - ask "who is the tenant of this row?".

Check yourself with the linter. Sections 1, 2, 3 and 6 should normally print `(0 rows)`. Sections 4 and 5
are informational: review tables without `org_id` and nullable foreign keys to ensure each is intentional.

```bash
docker compose exec -T postgres psql -U workshop -d saas -f /workshop/exercises/01-postgres/lint.sql
```

Then **try to break your own schema**. All of these must fail:

```sql
SET search_path = app;
-- (insert two orgs, a role in org 2, a user, then...)
-- 1) membership in org 1 with a role from org 2        -> composite FK violation
-- 2) two 'active' subscriptions for one org            -> partial unique violation
-- 3) invoice with negative total or status 'refunded'  -> CHECK violation
-- 4) two users 'Ann@x.com' and 'ann@x.com'            -> unique violation
```

## Part B - Make slow queries fast (10 min)

A different dataset: 2 million invoices, 1,000 tenants, one *whale* tenant (`org_id = 1`) owning 30 % of the rows.
There are no indexes yet.

```bash
docker compose exec -T postgres psql -U workshop -d saas -f /workshop/exercises/01-postgres/lab-seed.sql
docker compose exec postgres psql -U workshop -d saas      # then:  SET search_path = lab;
```

For each query: run `EXPLAIN (ANALYZE, BUFFERS)`, write down the plan node and the time, create **one** index,
run it again, compare. Don't change the queries.

```sql
-- Q1  endpoint 3: first page for the whale tenant
SELECT id, number, total_cents, issued_at FROM invoices
WHERE org_id = 1 AND status = 'open' ORDER BY issued_at DESC LIMIT 20;

-- Q2  endpoint 4: single invoice by (tenant, number)
SELECT * FROM invoices WHERE org_id = 42 AND number = 'INV-42-3';

-- Q3  revenue dashboard: paid revenue per month, last 12 months
SELECT date_trunc('month', issued_at) AS month, sum(total_cents)
FROM invoices
WHERE org_id = 42 AND status = 'paid' AND issued_at > now() - interval '12 months'
GROUP BY 1 ORDER BY 1;
```

Questions to answer while you work:
- Which column goes first in a composite index, and why? (equality columns first, then the sort/range column)
- Why does Q1 no longer need a `Sort` node?
- What does `Index Only Scan` need? (`INCLUDE`, `VACUUM`) Is the partial index (`WHERE status = 'paid'`) smaller?
- What happens to **write** speed if you add 10 more indexes?

## Part C - Align schema and API (5 min)

Fill in the table (copy it into a text file, or fill the blanks in your head and say it to your pair):

| Endpoint | Tables touched | Join keys | Index that serves it |
|---|---|---|---|
| `GET /orgs/{slug}/members` | ? | ? | ? |
| `GET /me/orgs` | ? | ? | ? |
| `GET /orgs/{slug}/invoices?status=open` | ? | ? | ? |
| authorization check (#7) | ? | ? | ? |

Write the SQL for the **authorization check** (endpoint 7) - one query, no loops. Which index makes it cheap?
How many round trips does `POST .../change-plan` need, and which statements must be in one transaction?

## Stretch goals (if you finish early)

1. **Row-Level Security**: enable RLS on `projects` with a policy using `current_setting('app.org_id')::bigint`.
   Test it with a non-superuser role (superusers bypass RLS!). Demo script: [`demos/04-multitenancy-rls.sql`](../../demos/04-multitenancy-rls.sql).
2. Add an **append-only audit log** table (`org_id`, `actor_id`, `action`, `entity`, `entity_id`, `at`). Should it be partitioned? By what?
3. Add `invoices.total_cents` consistency: write a trigger (or a query) that proves `total_cents = sum(quantity * unit_amount_cents)`.
4. Support **custom roles that inherit** from other roles. What does the model look like? Is a recursive CTE needed?

## Debrief questions (5 min)

- Where did two pairs make **different** decisions? Which one is cheaper to change later?
- Which constraint was hardest to express - and is it enforced by the database or only by hope (application code)?
- What would you change at 100 M invoices? (partitioning by `issued_at`, archiving, read replicas)

## Detailed walkthrough and common errors

### Set up and reset safely

1. Confirm Docker is running:

   ```bash
docker info
   ```

2. Start only the databases, or use the repository setup check:

   ```bash
docker compose up -d --wait
./scripts/check-setup.sh
   ```

3. Open PostgreSQL:

   ```bash
docker compose exec postgres psql -U workshop -d saas
   ```

Useful shell commands inside `psql` are `\dt`, `\d table_name`, `\d+ table_name`, `\x`, `\timing`, and `\q`.
The starter script is intentionally re-runnable: every run drops and recreates the `app` schema.

### Part A - detailed build sequence

1. **Model organizations and users first.** These tables are already provided. Copy their slug, email, and
   tenant semantics rather than inventing another URL identifier.
2. **Create roles and permissions.** Make a role per organization and add a unique `(org_id, name)` constraint.
   Keep permissions global. The `role_permissions` join table should use a composite primary key.
3. **Create memberships.** Use `PRIMARY KEY (org_id, user_id)` and the composite foreign key
   `(role_id, org_id) REFERENCES roles (id, org_id)`. Do not use only `role_id`; that allows a role from another
   tenant.
4. **Create plans and subscriptions.** Plans are global. Subscriptions belong to an organization and reference a
   plan. Keep historical subscriptions, but protect live subscriptions with a partial unique index:

   ```sql
CREATE UNIQUE INDEX subscriptions_one_live_per_org
    ON subscriptions (org_id)
    WHERE status IN ('trialing', 'active', 'past_due');
   ```

5. **Create invoices and invoice items.** Choose whether `total_cents` is stored or derived. Store it only if
   every write changes both the header and items in the same transaction. For either choice, never use a floating
   point column. Use `org_id, number` for uniqueness and API lookup.
6. **Create projects.** Store soft deletion as `archived_at` rather than deleting the row. Create a partial unique
   index on active names so archived projects can reuse a name:

   ```sql
CREATE UNIQUE INDEX projects_name_active_uq
    ON projects (org_id, lower(name))
    WHERE archived_at IS NULL;
   ```

7. **Create indexes only after the foreign keys.** The linter warns only about tables in `app`. Indexes use the
   leftmost-column rule: for a lookup by organization and status, put `org_id` and `status` before `issued_at`.

Run the starter and linter after each TODO:

```bash
docker compose exec -T postgres psql -U workshop -d saas \
  -f /workshop/exercises/01-postgres/starter.sql
docker compose exec -T postgres psql -U workshop -d saas \
  -f /workshop/exercises/01-postgres/lint.sql
```

A good linter run normally shows `(0 rows)` for sections 1, 2, 3, and 6. Sections 4 and 5 are informational:
review each finding. For example, section 5's `subscription_id` finding is acceptable if that relationship is
intentionally optional.

### Part A - force every constraint to fail

The following statements intentionally fail. Run them one at a time and confirm an `ERROR` rather than continuing
past the failure. The role and subscription tests may require IDs from your own seed data.

```sql
SET search_path = app;

-- 1. Cross-tenant role (must be rejected by a composite FK)
INSERT INTO memberships (org_id, user_id, role_id, status)
VALUES (1, 1, 999, 'active');

-- 2. A second live subscription (must be rejected by the partial unique index)
INSERT INTO subscriptions (org_id, plan_id, status,
                           current_period_start, current_period_end)
VALUES (1, 1, 'active', now(), now() + interval '1 month');

-- 3. Negative invoice and unknown status (must be rejected by CHECK constraints)
INSERT INTO invoices (org_id, number, status, currency, total_cents)
VALUES (1, 'BAD-NEGATIVE', 'draft', 'EUR', -1);

INSERT INTO invoices (org_id, number, status, currency, total_cents)
VALUES (1, 'BAD-STATUS', 'refunded', 'EUR', 100);

-- 4. Mixed-case duplicate email (must be rejected by lower(email))
INSERT INTO users (email, full_name) VALUES ('Ann@x.com', 'Ann');
INSERT INTO users (email, full_name) VALUES ('ann@x.com', 'Ann again');
```

The exact row IDs may differ; the constraint names and fact that PostgreSQL rejects the statements are what matter.

### Part B - detailed query procedure

Load the dataset before running EXPLAIN:

```bash
docker compose exec -T postgres psql -U workshop -d saas \
  -f /workshop/exercises/01-postgres/lab-seed.sql
```

The seed normally takes 15--30 seconds and creates about 2 million rows in the `lab` schema.
For every query:

1. Start `psql` and set the search path:

   ```sql
SET search_path = lab;
   ```

2. Run `EXPLAIN (ANALYZE, BUFFERS)` before adding an index.
3. Record the top-level plan, execution time, and shared buffer reads.
4. Run exactly one `CREATE INDEX` statement.
5. Run `ANALYZE` or `VACUUM ANALYZE` when testing an index-only scan.
6. Re-run the identical query and compare the same measurements.

For Q1, equality columns belong first in the index and the descending sort column should last. PostgreSQL should
prefer a bounded index scan and stop after 20 rows. It should not perform a heap sort.

For Q2, the tenant and public invoice number form a key. A unique `(org_id, number)` index both creates a fast
lookup and prevents duplicate invoice numbers per tenant.

For Q3, consider a partial paid-invoice index plus `INCLUDE (total_cents)`. It is useful only because the query
filters `status = 'paid'`. Verify `Heap Fetches: 0` and the lack of table reads to confirm an index-only scan.
Visibility-map state can initially prevent the scan from being index-only; `VACUUM` updates that state.

Run the complete reference index set only after doing the comparison yourself:

```bash
docker compose exec -T postgres psql -U workshop -d saas \
  -f /workshop/exercises/01-postgres/solution/lab-indexes.sql
```

### Common PostgreSQL error messages

| Error or symptom | Likely cause | Fix |
|---|---|---|
| `schema "app" does not exist` | File was run outside `/workshop` or starter failed early | Re-run the starter and inspect the first preceding error |
| `psql: could not connect` | Docker or PostgreSQL is stopped | Run `docker compose up -d postgres` and `docker compose ps` |
| `relation "app.roles" does not exist` | TODO 1 was skipped or the script stopped at an earlier syntax error | Finish earlier TODOs before later foreign keys |
| `foreign key ... is not present in table "roles"` | Role belongs to a different organization | Store `(role_id, org_id)` together and use the composite FK |
| `duplicate key value violates unique constraint` | Re-running seed data or violating a unique rule | Inspect existing rows and choose a fresh test value |
| `violates check constraint` | Value is negative or outside an enum | Match the declared `CHECK` condition |
| `function lower(text) does not exist` | Wrong SQL dialect or missing PostgreSQL | You are probably not connected to the PostgreSQL container |
| EXPLAIN still uses `Seq Scan` | Planner thinks the table is small, statistics are stale, or the index is not usable | Run `ANALYZE`, check column order, and compare selectivity |
| EXPLAIN uses `Sort` after creating an index | Index column order or sort direction differs from the query | Put equality columns first and the sort/range column in the requested order |
| EXPLAIN says `Heap Fetches` | Table pages are needed by the visibility map or INCLUDE is incomplete | Run `VACUUM`, include only columns required by the query |
| `port is already allocated` | Host port 5432 is used by another container or PostgreSQL | Stop the conflicting service or change host port `5433:5432` |

> **Warning:** Running `solution/schema.sql` drops and recreates the `app` schema, replacing your database work.
> Read it in your editor or save your work before running it.

Reference solution (look only after you tried!): [`solution/schema.sql`](solution/schema.sql),
[`solution/lab-indexes.sql`](solution/lab-indexes.sql), [`solution/api-mapping.md`](solution/api-mapping.md).
