-- DEMO 1: normalization vs denormalization   (run top to bottom, narrate the anomalies)
--   docker compose exec -T postgres psql -U workshop -d saas -f /workshop/demos/01-normalization.sql
DROP SCHEMA IF EXISTS demo1 CASCADE; CREATE SCHEMA demo1; SET search_path = demo1;
\echo '=== 1. The "spreadsheet" table: one row per order line, customer and product copied everywhere'
CREATE TABLE orders_flat (
    order_id int, customer_email text, customer_name text, customer_city text,
    product_sku text, product_name text, product_price numeric, qty int
);
INSERT INTO orders_flat VALUES
 (1,'ann@x.com','Ann','Berlin','P1','Keyboard',50,1),
 (1,'ann@x.com','Ann','Berlin','P2','Mouse',20,2),
 (2,'ann@x.com','Ann','Berlin','P2','Mouse',20,1),
 (3,'bob@x.com','Bob','Paris' ,'P1','Keyboard',50,3);

\echo '--- UPDATE ANOMALY: Ann moves. We update only one row...'
UPDATE orders_flat SET customer_city = 'Munich' WHERE order_id = 1 AND product_sku = 'P1';
SELECT DISTINCT customer_email, customer_city FROM orders_flat WHERE customer_email = 'ann@x.com';   -- two cities for one person
\echo '--- DELETE ANOMALY: delete order 3 -> we forget Bob and the Keyboard price existed? (Bob gone; Keyboard still elsewhere)'
\echo '--- INSERT ANOMALY: you cannot store a customer or a product that has no order yet.'

\echo
\echo '=== 2. Normalized (3NF): every fact stored once'
CREATE TABLE customers (id int PRIMARY KEY, email text UNIQUE NOT NULL, name text NOT NULL, city text NOT NULL);
CREATE TABLE products  (sku text PRIMARY KEY, name text NOT NULL, price_cents int NOT NULL CHECK (price_cents >= 0));
CREATE TABLE orders    (id int PRIMARY KEY, customer_id int NOT NULL REFERENCES customers, placed_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE order_lines (
    order_id int REFERENCES orders, line_no int, sku text NOT NULL REFERENCES products,
    qty int NOT NULL CHECK (qty > 0),
    unit_price_cents int NOT NULL,           -- <- NOT a violation: a historical SNAPSHOT of the price at purchase time
    PRIMARY KEY (order_id, line_no)
);
INSERT INTO customers VALUES (1,'ann@x.com','Ann','Munich'),(2,'bob@x.com','Bob','Paris');
INSERT INTO products VALUES ('P1','Keyboard',5000),('P2','Mouse',2000);
INSERT INTO orders (id, customer_id) VALUES (1,1),(2,1),(3,2);
INSERT INTO order_lines VALUES (1,1,'P1',1,5000),(1,2,'P2',2,2000),(2,1,'P2',1,2000),(3,1,'P1',3,5000);
SELECT c.name, o.id AS order_id, sum(l.qty * l.unit_price_cents) AS total_cents
FROM orders o JOIN customers c ON c.id = o.customer_id JOIN order_lines l ON l.order_id = o.id GROUP BY 1, 2 ORDER BY 2;

\echo
\echo '=== 3. Deliberate denormalization #1: stored aggregate (orders.total_cents)'
ALTER TABLE orders ADD COLUMN total_cents bigint;
UPDATE orders o SET total_cents = (SELECT sum(qty * unit_price_cents) FROM order_lines WHERE order_id = o.id);
\echo 'Rule: denormalize only with (a) a measured read problem, (b) ONE owner of the write path, (c) a way to verify/repair:'
SELECT o.id, o.total_cents, x.real_total FROM orders o
JOIN LATERAL (SELECT sum(qty * unit_price_cents) AS real_total FROM order_lines WHERE order_id = o.id) x ON true
WHERE o.total_cents IS DISTINCT FROM x.real_total;    -- the "drift detector": must return 0 rows

\echo
\echo '=== 4. Deliberate denormalization #2: materialized view = a rebuildable cache INSIDE the database'
CREATE MATERIALIZED VIEW revenue_by_city AS
  SELECT c.city, sum(o.total_cents) AS revenue_cents FROM orders o JOIN customers c ON c.id = o.customer_id GROUP BY 1;
CREATE UNIQUE INDEX ON revenue_by_city (city);          -- required for CONCURRENTLY refresh (no read lock)
REFRESH MATERIALIZED VIEW CONCURRENTLY revenue_by_city;
SELECT * FROM revenue_by_city;

\echo
\echo '=== 5. jsonb is denormalization too - fine for sparse, rarely filtered attributes, bad for core relations'
ALTER TABLE products ADD COLUMN attrs jsonb NOT NULL DEFAULT '{}';
UPDATE products SET attrs = '{"color":"black","layout":"US"}' WHERE sku = 'P1';
SELECT sku, attrs->>'color' AS color FROM products;
