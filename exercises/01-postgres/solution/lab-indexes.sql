-- Exercise 1 / Part B - reference solution.  Run AFTER lab-seed.sql, then re-run the EXPLAINs.
SET search_path = lab;

-- Q1  GET /orgs/{slug}/invoices?status=open        (newest first, page size 20)
--     Equality columns first (org_id, status), then the ORDER BY column -> no sort, stops after 20 rows.
CREATE INDEX invoices_org_status_issued_idx ON invoices (org_id, status, issued_at DESC);

-- Q2  GET /orgs/{slug}/invoices/{number}
--     A tenant-scoped UNIQUE index: enforces the business rule AND serves the lookup.
CREATE UNIQUE INDEX invoices_org_number_uq ON invoices (org_id, number);

-- Q3  GET /orgs/{slug}/reports/revenue   (paid, last 12 months, per month)
--     Partial index (only paid rows) that INCLUDEs the summed column -> index-only scan.
CREATE INDEX invoices_org_paid_issued_idx ON invoices (org_id, issued_at) INCLUDE (total_cents) WHERE status = 'paid';

VACUUM ANALYZE invoices;   -- refresh stats + visibility map (needed for index-only scans)
