-- DEMO 5: a "production" schema full of common mistakes.  Run, then lint it and discuss each line.
--   docker compose exec -T postgres psql -U workshop -d saas -f /workshop/demos/05-mistakes.sql
--   docker compose exec -T postgres psql -U workshop -d saas -v schema=bad -f /workshop/exercises/01-postgres/lint.sql
-- Game: split the room in two, give each team 3 minutes to find as many problems as possible before you reveal.
DROP SCHEMA IF EXISTS bad CASCADE; CREATE SCHEMA bad; SET search_path = bad;

CREATE TABLE customer (                          -- (1) no primary key; (2) email not unique; (3) varchar(255) "just in case"
    id          int,
    email       varchar(255),
    name        varchar(255),
    created     timestamp,                       -- (4) timestamp WITHOUT time zone: which zone? DST?
    status      int                              -- (5) magic number: 0,1,2... nobody remembers. Use text + CHECK.
);

CREATE TABLE orders (
    id          serial PRIMARY KEY,
    customer_id int,                             -- (6) no FOREIGN KEY, nullable, no index -> orphans + slow joins
    total       float,                           -- (7) float money: 0.1 + 0.2 <> 0.3.  Use integer cents / numeric
    currency    text,                            -- (8) no currency code constraint
    deleted     boolean DEFAULT false            -- (9) soft delete without partial unique indexes -> "name already taken" for deleted rows
);

CREATE TABLE settings (                          -- (10) EAV: "flexibility" that gives up types, constraints and sane queries
    entity_id int, key text, value text
);
-- SELECT ... FROM settings a JOIN settings b ON ... JOIN settings c ON ...   <- every attribute is another self-join

CREATE TABLE order_events (                      -- (11) jsonb dumping ground for data you FILTER and JOIN on every day
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),   -- (12) random UUIDv4 PK: inserts scatter across the whole b-tree (use bigint, or UUIDv7)
    body jsonb
);

CREATE TABLE tags (order_id int, tag_csv text);  -- (13) comma-separated list in a column: no FK, no index, no integrity. Use a join table or text[]

-- (14) Not in DDL: OFFSET 100000 pagination, SELECT * in APIs, N+1 queries in the ORM, a 3-hour transaction around an HTTP call,
--      migrations that rewrite a 500M-row table under an ACCESS EXCLUSIVE lock, no backups ever restored, one superuser for the app.

\echo 'Float money demo:'
SELECT (0.1::float + 0.2::float) = 0.3::float AS float_equal, (0.1::numeric + 0.2::numeric) = 0.3::numeric AS numeric_equal;
\echo 'Soft delete demo: deleted row blocks the name'
CREATE TABLE users_bad (id serial PRIMARY KEY, email text UNIQUE NOT NULL, deleted boolean DEFAULT false);
INSERT INTO users_bad (email, deleted) VALUES ('ann@x.com', true);
INSERT INTO users_bad (email) VALUES ('ann@x.com');      -- ERROR: the "deleted" user still owns the e-mail. Fix: partial unique index WHERE NOT deleted
