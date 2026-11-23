-- =====================================================================
-- Exercise 1 - PART B: the index lab dataset (independent from your own schema).
-- Creates schema `lab` with 1,000 tenants and ~2,000,000 invoices.  Takes ~15-30 s.
--   docker compose exec -T postgres psql -U workshop -d saas -f /workshop/exercises/01-postgres/lab-seed.sql
-- Tenant 1 is a huge "whale" customer (about 30% of all rows) - a classic noisy neighbour.
-- No indexes except the primary key. Making it fast is YOUR job.
-- =====================================================================

DROP SCHEMA IF EXISTS lab CASCADE;
CREATE SCHEMA lab;

CREATE TABLE lab.invoices (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    org_id      integer     NOT NULL,
    number      text        NOT NULL,
    status      text        NOT NULL,
    total_cents bigint      NOT NULL,
    issued_at   timestamptz NOT NULL,
    note        text
);

SELECT setseed(0.42);   -- deterministic data: everyone sees the same numbers
INSERT INTO lab.invoices (org_id, number, status, total_cents, issued_at, note)
SELECT org_id,
       'INV-' || org_id || '-' || row_number() OVER (PARTITION BY org_id ORDER BY issued_at),
       CASE WHEN r < 0.80 THEN 'paid' WHEN r < 0.95 THEN 'open' WHEN r < 0.99 THEN 'void' ELSE 'draft' END,
       (1000 + floor(random() * 99000))::bigint,
       issued_at,
       md5(g::text)
FROM (
    SELECT g,
           CASE WHEN random() < 0.30 THEN 1 ELSE 2 + floor(random() * 999)::int END AS org_id,
           random() AS r,
           now() - (random() * interval '3 years') AS issued_at
    FROM generate_series(1, 2000000) g
) s;

ANALYZE lab.invoices;

SELECT count(*) AS invoices,
       count(DISTINCT org_id) AS tenants,
       count(*) FILTER (WHERE org_id = 1) AS whale_invoices,
       pg_size_pretty(pg_total_relation_size('lab.invoices')) AS size
FROM lab.invoices;
