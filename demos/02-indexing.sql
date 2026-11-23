-- DEMO 2: indexes and query plans   (needs ~15 s to build, then narrate each EXPLAIN)
--   docker compose exec -T postgres psql -U workshop -d saas -f /workshop/demos/02-indexing.sql
\timing off
DROP SCHEMA IF EXISTS demo2 CASCADE; CREATE SCHEMA demo2; SET search_path = demo2;
CREATE TABLE users (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, org_id int NOT NULL, email text NOT NULL,
                    status text NOT NULL, created_at timestamptz NOT NULL, bio text);
INSERT INTO users (org_id, email, status, created_at, bio)
SELECT 1 + (g % 500), 'user' || g || '@Example.com', CASE WHEN g % 100 = 0 THEN 'suspended' ELSE 'active' END,
       now() - (g || ' minutes')::interval, repeat('x', 100)
FROM generate_series(1, 1000000) g;
ANALYZE users;

\echo '=== 1. No index: Seq Scan (reads the whole table)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT * FROM users WHERE email = 'user777777@Example.com';

\echo '=== 2. B-tree index -> Index Scan. compare Buffers and Execution Time with the Seq Scan above'
CREATE INDEX users_email_idx ON users (email);
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF) SELECT * FROM users WHERE email = 'user777777@Example.com';

\echo '=== 3. Function on the column kills the index (non-sargable). Fix: expression index'
EXPLAIN (ANALYZE, COSTS OFF) SELECT * FROM users WHERE lower(email) = 'user777777@example.com';
CREATE INDEX users_email_lower_idx ON users (lower(email));
EXPLAIN (ANALYZE, COSTS OFF) SELECT * FROM users WHERE lower(email) = 'user777777@example.com';

\echo '=== 4. Composite index: column ORDER matters. (org_id, created_at) serves org filter + sort'
CREATE INDEX users_org_created_idx ON users (org_id, created_at DESC);
EXPLAIN (ANALYZE, COSTS OFF) SELECT * FROM users WHERE org_id = 7 ORDER BY created_at DESC LIMIT 10;      -- no Sort node
EXPLAIN (ANALYZE, COSTS OFF) SELECT * FROM users WHERE created_at > now() - interval '1 hour';             -- leading column missing: scans the WHOLE index (or table), ~100x slower than the line above

\echo '=== 5. Low selectivity: index on status (99% active) is ignored for "active", used for "suspended" -> PARTIAL index'
CREATE INDEX users_status_idx ON users (status);
EXPLAIN (ANALYZE, COSTS OFF) SELECT count(*) FROM users WHERE status = 'active';
EXPLAIN (ANALYZE, COSTS OFF) SELECT id FROM users WHERE status = 'suspended' LIMIT 5000;
DROP INDEX users_status_idx;
CREATE INDEX users_suspended_idx ON users (org_id) WHERE status = 'suspended';
SELECT pg_size_pretty(pg_relation_size('users_suspended_idx')) AS partial_size, pg_size_pretty(pg_relation_size('users_email_idx')) AS full_size;

\echo '=== 6. Covering index -> Index Only Scan (heap not touched)'
CREATE INDEX users_org_cover_idx ON users (org_id) INCLUDE (email);
VACUUM ANALYZE users;
EXPLAIN (ANALYZE, COSTS OFF) SELECT email FROM users WHERE org_id = 7;

\echo '=== 7. LIKE with leading wildcard cannot use a b-tree. Needs pg_trgm (GIN)'
EXPLAIN (ANALYZE, COSTS OFF) SELECT * FROM users WHERE email LIKE '%777777%';
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX users_email_trgm ON users USING gin (email gin_trgm_ops);
EXPLAIN (ANALYZE, COSTS OFF) SELECT * FROM users WHERE email LIKE '%777777%';

\echo '=== 8. Indexes are not free: every index is paid for on every INSERT/UPDATE and in disk space'
SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid)) AS size, idx_scan
FROM pg_stat_user_indexes WHERE schemaname = 'demo2' ORDER BY pg_relation_size(indexrelid) DESC;
SELECT pg_size_pretty(pg_relation_size('users')) AS table_size, pg_size_pretty(pg_indexes_size('users')) AS all_indexes;
