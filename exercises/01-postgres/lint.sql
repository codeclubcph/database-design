-- =====================================================================
-- Schema linter: works on ANY schema you design in `app`.
--   docker compose exec -T postgres psql -U workshop -d saas -f /workshop/exercises/01-postgres/lint.sql
-- Sections 1, 2, 3 and 6 should normally return zero rows.
-- Sections 4 and 5 are informational; review each finding for intentional design.
-- =====================================================================
\pset null '(null)'
\if :{?schema}
\else
  \set schema app
\endif
-- lint another schema with:  psql ... -v schema=bad -f lint.sql
\set ON_ERROR_STOP off

\echo
\echo '== 1. Tables without a primary key'
SELECT c.relname AS table_name
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = :'schema' AND c.relkind = 'r'
  AND NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype = 'p');

\echo
\echo '== 2. Foreign keys with no supporting index (slow joins and slow parent deletes)'
SELECT c.conrelid::regclass AS table_name, c.conname AS fk,
       pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c
JOIN pg_namespace n ON n.oid = c.connamespace
WHERE c.contype = 'f' AND n.nspname = :'schema'
  AND NOT EXISTS (
        SELECT 1 FROM pg_index i
        WHERE i.indrelid = c.conrelid
          AND (i.indkey::int2[])[0:cardinality(c.conkey) - 1] @> c.conkey   -- FK columns are a leading prefix
          AND c.conkey @> (i.indkey::int2[])[0:cardinality(c.conkey) - 1]
  );

\echo
\echo '== 3. Dangerous column types (float/real money, timestamp without time zone)'
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = :'schema'
  AND (data_type IN ('real', 'double precision', 'money', 'timestamp without time zone')
       OR (column_name ~ '(price|amount|total|cents)' AND data_type NOT IN ('integer', 'bigint', 'numeric', 'smallint')));

\echo
\echo '== 4. Tenant-owned tables with no org_id  (info: is each of these truly global or child-of-tenant?)'
SELECT t.table_name
FROM information_schema.tables t
WHERE t.table_schema = :'schema' AND t.table_type = 'BASE TABLE'
  AND NOT EXISTS (SELECT 1 FROM information_schema.columns c
                  WHERE c.table_schema = :'schema' AND c.table_name = t.table_name AND c.column_name = 'org_id')
ORDER BY 1;

\echo
\echo '== 5. Nullable columns that are foreign keys (is "no parent" really valid?)'
SELECT cl.relname AS table_name, a.attname AS column_name
FROM pg_constraint c
JOIN pg_class cl ON cl.oid = c.conrelid
JOIN pg_namespace n ON n.oid = cl.relnamespace
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
WHERE c.contype = 'f' AND n.nspname = :'schema' AND NOT a.attnotnull;

\echo
\echo '== 6. Redundant indexes (same leading columns as another index on the table)'
SELECT a.indrelid::regclass AS table_name, a.indexrelid::regclass AS redundant_index, b.indexrelid::regclass AS covered_by
FROM pg_index a JOIN pg_index b
  ON a.indrelid = b.indrelid AND a.indexrelid <> b.indexrelid
 AND a.indkey::text = array_to_string((b.indkey::int2[])[0:array_length(a.indkey, 1) - 1], ' ')
 AND NOT a.indisunique AND a.indpred IS NULL AND b.indpred IS NULL
JOIN pg_class c ON c.oid = a.indrelid JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = :'schema';

\echo
\echo '== Summary: tables in the schema'
SELECT count(*) AS tables FROM information_schema.tables WHERE table_schema = :'schema' AND table_type = 'BASE TABLE';
