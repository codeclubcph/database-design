# Part C - API alignment (reference answers)

| Endpoint | Tables touched | Join keys | Index that serves it |
|---|---|---|---|
| `GET /orgs/{slug}/members` | `organizations` -> `memberships` -> `users`, `roles` | `slug` -> `org_id`; `memberships.user_id`; `(role_id, org_id)` | `organizations.slug` (unique), PK `memberships(org_id, user_id)` (leading `org_id`) |
| `GET /me/orgs` | `memberships` -> `organizations` | `user_id`; `org_id` | `memberships_user_idx (user_id)` - the PK starts with `org_id`, so it can NOT serve this lookup |
| `GET /orgs/{slug}/invoices?status=open` | `organizations` -> `invoices` | `org_id` | `invoices (org_id, status, issued_at DESC, id DESC)` |
| `GET /orgs/{slug}/invoices/{number}` | `invoices` + `invoice_items` | `(org_id, number)`; `invoice_id` | unique `(org_id, number)`, `invoice_items (invoice_id)` |
| authorization check | `memberships` -> `role_permissions` -> `permissions` | `(org_id, user_id)`; `role_id`; `permission_id` | PK lookups only: membership PK, `role_permissions` PK `(role_id, permission_id)`, `permissions.key` unique |

## Authorization check - one query

```sql
SELECT EXISTS (
    SELECT 1
    FROM app.organizations o
    JOIN app.memberships   m  ON m.org_id = o.id
    JOIN app.role_permissions rp ON rp.role_id = m.role_id
    JOIN app.permissions   p  ON p.id = rp.permission_id
    WHERE o.slug      = $1          -- 'acme'
      AND o.deleted_at IS NULL
      AND m.user_id   = $2
      AND m.status    = 'active'
      AND p.key       = $3          -- 'invoice:write'
) AS allowed;
```

Every hop is a primary-key or unique-key lookup, so it is a handful of index probes. Because it runs on every
request, in real systems the result is also cached per (user, org) for a few seconds, or the permission list is
embedded in a signed token (trade-off: revocation delay).

## Keyset pagination (endpoint 3)

```sql
-- first page
SELECT number, status, total_cents, issued_at, id
FROM app.invoices WHERE org_id = $1 AND status = 'open'
ORDER BY issued_at DESC, id DESC LIMIT 20;

-- next page: the client sends the last (issued_at, id) it saw as an opaque cursor
SELECT number, status, total_cents, issued_at, id
FROM app.invoices WHERE org_id = $1 AND status = 'open'
  AND (issued_at, id) < ($2, $3)
ORDER BY issued_at DESC, id DESC LIMIT 20;
```

`OFFSET 100000` reads and throws away 100,000 rows; keyset always costs the same. The index
`(org_id, status, issued_at DESC, id DESC)` matches the `ORDER BY` exactly.

## change-plan must be atomic

```sql
BEGIN;
  -- lock this org's live subscription so two concurrent requests serialize
  SELECT id FROM app.subscriptions
  WHERE org_id = $1 AND status IN ('trialing','active','past_due') FOR UPDATE;

  UPDATE app.subscriptions SET status = 'canceled', canceled_at = now() WHERE id = $2;
  INSERT INTO app.subscriptions (org_id, plan_id, status, current_period_start, current_period_end)
  VALUES ($1, $3, 'active', now(), now() + interval '1 month');
COMMIT;
```

Without the transaction a crash between the two statements leaves the org with no subscription. Without
the partial unique index, two concurrent requests could leave it with two - the database is the last line of defence.
