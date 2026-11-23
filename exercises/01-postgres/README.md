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

Check yourself with the linter. Every section should print `(0 rows)` (section 4 is informational):

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

Reference solution (look only after you tried!): [`solution/schema.sql`](solution/schema.sql),
[`solution/lab-indexes.sql`](solution/lab-indexes.sql), [`solution/api-mapping.md`](solution/api-mapping.md).
