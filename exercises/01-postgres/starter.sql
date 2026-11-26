-- =====================================================================
-- Exercise 1 - PART A: design the SaaS schema      (~15 min)
-- =====================================================================
-- Fill in every  -- TODO.  Run it as many times as you like:
--
--   docker compose exec -T postgres psql -U workshop -d saas -f /workshop/exercises/01-postgres/starter.sql
--
-- The script drops and recreates the `app` schema, so it is always safe to re-run.
-- Read exercises/01-postgres/README.md first for the business rules.
-- =====================================================================

DROP SCHEMA IF EXISTS app CASCADE;
CREATE SCHEMA app;
SET search_path = app;

-- ---------------------------------------------------------------------
-- Given: tenants and users (already done for you - study the choices)
-- ---------------------------------------------------------------------
CREATE TABLE organizations (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    slug        text        NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9-]{3,40}$'),  -- used in URLs: /orgs/{slug}
    name        text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    deleted_at  timestamptz                                                      -- soft delete
);

CREATE TABLE users (                     -- a user is GLOBAL, not owned by one org
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email       text        NOT NULL,
    full_name   text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX users_email_uq ON users (lower(email));   -- case-insensitive uniqueness

-- ---------------------------------------------------------------------
-- TODO 1: roles, permissions, role_permissions
--   * Roles are defined PER ORGANIZATION (each org can edit its own).
--   * Permissions are global, identified by a key like 'invoice:read'.
--   * A role has many permissions, a permission belongs to many roles.
--   * Role names are unique within an org.
--   Hint: add UNIQUE (id, org_id) on roles - you will need it in TODO 2.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- TODO 2: memberships
--   * A user can belong to many orgs, with exactly ONE role per org.
--   * Status: invited / active / suspended.
--   * It must be IMPOSSIBLE to give a user a role that belongs to another org.
--     (Hint: composite foreign key  (role_id, org_id) -> roles (id, org_id).)
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- TODO 3: plans and subscriptions
--   * plans: global catalogue (code, name, monthly price, currency, limits).
--   * subscriptions: which org is on which plan, with a status
--     (trialing / active / past_due / canceled) and the current billing period.
--   * An org may have MANY subscriptions over time, but at most ONE live one
--     (trialing / active / past_due).  Hint: partial unique index.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- TODO 4: invoices and invoice_items
--   * Invoice belongs to an org (and optionally to a subscription).
--   * Human-readable number, unique per org (not globally!).
--   * Money: integer minor units + currency code. NEVER float.
--   * Status: draft / open / paid / void.
--   * Items: description, quantity, unit amount.
--   * Decide: store invoices.total_cents or compute it? Write your reasoning below.
-- ---------------------------------------------------------------------


-- Reasoning on total_cents:


-- ---------------------------------------------------------------------
-- TODO 5: projects (the "business" entity the customers actually use)
--   * Belongs to an org, created by a user, can be archived.
--   * Project names unique per org among non-archived projects.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- TODO 6: indexes
--   Postgres does NOT index foreign keys automatically.
--   Add the indexes your API will need - then run lint.sql to see what you missed.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- Seed data (works once your tables use the names/columns from the README)
-- Uncomment when ready.
-- ---------------------------------------------------------------------
-- INSERT INTO permissions (key) VALUES ('invoice:read'), ('invoice:write'), ('project:read'), ('project:write'), ('member:manage');
