-- DEMO 3: transactions, locking, isolation.  Needs TWO terminals ("A" and "B"), both:
--   docker compose exec postgres psql -U workshop -d saas
-- Paste the blocks in the order shown.  Setup (run once, in A):
DROP SCHEMA IF EXISTS demo3 CASCADE; CREATE SCHEMA demo3; SET search_path = demo3;
CREATE TABLE accounts (id int PRIMARY KEY, balance_cents bigint NOT NULL CHECK (balance_cents >= 0));
INSERT INTO accounts VALUES (1, 10000), (2, 0);
CREATE TABLE admins (user_id int PRIMARY KEY, org_id int NOT NULL);
INSERT INTO admins VALUES (1, 7), (2, 7);
CREATE TABLE jobs (id serial PRIMARY KEY, payload text, state text NOT NULL DEFAULT 'queued');
INSERT INTO jobs (payload) SELECT 'job ' || g FROM generate_series(1, 6) g;

-- ======================================================================
-- 1. LOST UPDATE (read-modify-write in the application, READ COMMITTED)
-- ======================================================================
-- A: BEGIN; SELECT balance_cents FROM demo3.accounts WHERE id = 1;     -- 10000, app computes 10000 - 3000
-- B: BEGIN; SELECT balance_cents FROM demo3.accounts WHERE id = 1;     -- 10000, app computes 10000 - 5000
-- A: UPDATE demo3.accounts SET balance_cents = 7000 WHERE id = 1; COMMIT;
-- B: UPDATE demo3.accounts SET balance_cents = 5000 WHERE id = 1; COMMIT;   -- A's withdrawal vanished. No error!
--
-- FIX 1 - let the database do the arithmetic (atomic, one statement):
--    UPDATE demo3.accounts SET balance_cents = balance_cents - 3000 WHERE id = 1 AND balance_cents >= 3000;   -- check rows affected = 1
-- FIX 2 - pessimistic lock:   SELECT ... FOR UPDATE   (B waits until A commits, then sees the new value)
-- FIX 3 - optimistic lock:    UPDATE ... SET ..., version = version + 1 WHERE id = 1 AND version = <what I read>  -- 0 rows = conflict, retry

-- ======================================================================
-- 2. ROW LOCKS BLOCK WRITERS, NOT READERS (MVCC)
-- ======================================================================
-- A: BEGIN; UPDATE demo3.accounts SET balance_cents = balance_cents - 1 WHERE id = 1;     -- do NOT commit yet
-- B: SELECT * FROM demo3.accounts;                                    -- returns immediately, old value (readers never block)
-- B: UPDATE demo3.accounts SET balance_cents = balance_cents - 1 WHERE id = 1;    -- hangs: waiting for A
-- C (3rd terminal): SELECT pid, wait_event_type, wait_event, state, left(query, 60) FROM pg_stat_activity WHERE datname = 'saas';
-- A: COMMIT;                                                          -- B continues
-- LESSON: long transactions hold locks and block others. Never keep a transaction open while calling an HTTP API.

-- ======================================================================
-- 3. DEADLOCK (opposite lock order)
-- ======================================================================
-- A: BEGIN; UPDATE demo3.accounts SET balance_cents = balance_cents + 1 WHERE id = 1;
-- B: BEGIN; UPDATE demo3.accounts SET balance_cents = balance_cents + 1 WHERE id = 2;
-- A: UPDATE demo3.accounts SET balance_cents = balance_cents + 1 WHERE id = 2;     -- waits for B
-- B: UPDATE demo3.accounts SET balance_cents = balance_cents + 1 WHERE id = 1;     -- ERROR: deadlock detected (Postgres kills one)
-- FIX: always lock rows in a consistent order (ORDER BY id ... FOR UPDATE), and retry on SQLSTATE 40P01.

-- ======================================================================
-- 4. JOB QUEUE WITHOUT CONTENTION: FOR UPDATE SKIP LOCKED
-- ======================================================================
-- A: BEGIN; SELECT id FROM demo3.jobs WHERE state = 'queued' ORDER BY id LIMIT 2 FOR UPDATE SKIP LOCKED;   -- gets 1,2
-- B: BEGIN; SELECT id FROM demo3.jobs WHERE state = 'queued' ORDER BY id LIMIT 2 FOR UPDATE SKIP LOCKED;   -- gets 3,4 (does not wait!)
-- A, B: COMMIT;

-- ======================================================================
-- 5. WRITE SKEW: "an organization must always keep at least one admin"
-- ======================================================================
-- Both admins demote themselves at the same moment. Each check sees the OTHER admin still there.
-- A: BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT count(*) FROM demo3.admins WHERE org_id = 7;     -- 2, ok to leave
-- B: BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT count(*) FROM demo3.admins WHERE org_id = 7;     -- 2, ok to leave
-- A: DELETE FROM demo3.admins WHERE user_id = 1; COMMIT;
-- B: DELETE FROM demo3.admins WHERE user_id = 2; COMMIT;           -- succeeds! Org has 0 admins. Repeatable read does NOT prevent this.
-- (reset: INSERT INTO demo3.admins VALUES (1,7),(2,7) ON CONFLICT DO NOTHING;)
--
-- FIX 1: BEGIN ISOLATION LEVEL SERIALIZABLE in both -> one commit fails with SQLSTATE 40001. App MUST retry.
-- FIX 2: lock a row everyone must touch:  SELECT * FROM demo3.organizations ... FOR UPDATE  (or pg_advisory_xact_lock(org_id))
-- FIX 3: make the DB enforce it (hard for this rule - a good "when constraints are not enough" example).

-- ======================================================================
-- 6. Isolation levels in one table (for the slide)
--   READ COMMITTED  (default)  each STATEMENT sees a fresh snapshot.  Allows: non-repeatable reads, lost updates (read-modify-write), write skew
--   REPEATABLE READ            one snapshot per TRANSACTION.          Prevents lost updates (errors 40001), allows write skew
--   SERIALIZABLE               as if one at a time.                   Prevents all; you MUST retry on 40001
-- ======================================================================
