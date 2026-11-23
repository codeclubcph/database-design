-- DEMO 4: multi-tenancy in one shared schema, and Row-Level Security as a safety net
--   docker compose exec -T postgres psql -U workshop -d saas -f /workshop/demos/04-multitenancy-rls.sql
-- Three isolation models (slide): 1) shared tables + tenant_id  2) schema per tenant  3) database per tenant.
-- This demo = model 1, the default for most SaaS products.
DROP SCHEMA IF EXISTS demo4 CASCADE; CREATE SCHEMA demo4; SET search_path = demo4;
DROP ROLE IF EXISTS app_user;
CREATE ROLE app_user LOGIN NOSUPERUSER;                 -- the application's role (NOT the owner, NOT a superuser)

CREATE TABLE projects (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    org_id bigint NOT NULL,
    name text NOT NULL
);
CREATE INDEX ON projects (org_id);                      -- every tenant table: org_id FIRST in its indexes
INSERT INTO projects (org_id, name) VALUES (1,'Acme website'), (1,'Acme mobile'), (2,'Globex migration');
GRANT USAGE ON SCHEMA demo4 TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON projects TO app_user;

\echo '=== 1. Without RLS the app is one forgotten WHERE org_id = ... away from a data breach'
SET ROLE app_user;
SELECT * FROM projects;                                 -- sees ALL tenants
RESET ROLE;

\echo '=== 2. Enable RLS: the database adds the filter to every statement'
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON projects
    USING      (org_id = current_setting('app.org_id', true)::bigint)    -- which rows are visible / updatable
    WITH CHECK (org_id = current_setting('app.org_id', true)::bigint);   -- which rows may be written
SET ROLE app_user;
SELECT count(*) AS visible_without_setting FROM projects;               -- 0: fail CLOSED when the context is missing

BEGIN;
SELECT set_config('app.org_id', '1', true);                              -- true = local to this transaction (pool-safe!)
SELECT * FROM projects;                                                  -- only Acme
EXPLAIN (COSTS OFF) SELECT * FROM projects WHERE name = 'x';             -- policy is just an extra filter: org_id index is used
\echo '--- writing a row for ANOTHER tenant must fail:'
SAVEPOINT s;
INSERT INTO projects (org_id, name) VALUES (2, 'sneaky');
ROLLBACK TO s;
COMMIT;
RESET ROLE;

\echo '=== 3. Gotchas to say out loud'
\echo '  * Superusers and the table OWNER bypass RLS (unless FORCE ROW LEVEL SECURITY). Test with a real app role.'
\echo '  * Use set_config(..., true) inside a transaction with connection pools; a session-level SET leaks to the next request.'
\echo '  * RLS is defence in depth, not a replacement for tenant-aware indexes, composite FKs and application checks.'
\echo '  * Noisy neighbour: one huge tenant can still hurt others -> statement_timeout, per-tenant rate limits, or move the whale to its own DB.'
\echo '  * Compare: schema-per-tenant = 5,000 tenants x 40 tables = 200,000 tables -> migrations and pg_catalog bloat.'

\echo '=== 4. Tenant-safe foreign keys (no RLS needed): child rows must carry the SAME org_id as the parent'
ALTER TABLE projects ADD UNIQUE (id, org_id);
CREATE TABLE tasks (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    org_id bigint NOT NULL,
    project_id bigint NOT NULL,
    title text NOT NULL,
    FOREIGN KEY (project_id, org_id) REFERENCES projects (id, org_id)    -- needs UNIQUE (id, org_id) on projects
);
