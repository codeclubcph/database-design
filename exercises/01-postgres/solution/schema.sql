-- =====================================================================
-- Exercise 1 - REFERENCE SOLUTION (one good answer, not THE answer)
-- WARNING: this drops and recreates the `app` schema, replacing your work.
-- docker compose exec -T postgres psql -U workshop -d saas -f /workshop/exercises/01-postgres/solution/schema.sql
-- =====================================================================

DROP SCHEMA IF EXISTS app CASCADE;
CREATE SCHEMA app;
SET search_path = app;

CREATE TABLE organizations (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    slug        text        NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9-]{3,40}$'),
    name        text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    deleted_at  timestamptz
);

CREATE TABLE users (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email       text        NOT NULL,
    full_name   text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX users_email_uq ON users (lower(email));

-- TODO 1 ---------------------------------------------------------------
CREATE TABLE roles (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    org_id      bigint NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    name        text   NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (org_id, name),
    UNIQUE (id, org_id)                -- target for composite FKs: "this role belongs to this org"
);

CREATE TABLE permissions (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    key         text NOT NULL UNIQUE CHECK (key ~ '^[a-z_]+:[a-z_]+$'),   -- 'invoice:read'
    description text
);

CREATE TABLE role_permissions (
    role_id       bigint NOT NULL REFERENCES roles (id)       ON DELETE CASCADE,
    permission_id bigint NOT NULL REFERENCES permissions (id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);
CREATE INDEX role_permissions_permission_idx ON role_permissions (permission_id);

-- TODO 2 ---------------------------------------------------------------
CREATE TABLE memberships (
    org_id      bigint NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    user_id     bigint NOT NULL REFERENCES users (id)         ON DELETE CASCADE,
    role_id     bigint NOT NULL,
    status      text   NOT NULL DEFAULT 'invited' CHECK (status IN ('invited', 'active', 'suspended')),
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (org_id, user_id),                                   -- one membership (and one role) per user per org
    FOREIGN KEY (role_id, org_id) REFERENCES roles (id, org_id)      -- cannot use another tenant's role
);
CREATE INDEX memberships_user_idx ON memberships (user_id);          -- "which orgs am I in?"
CREATE INDEX memberships_role_idx ON memberships (role_id, org_id);  -- FK support index

-- TODO 3 ---------------------------------------------------------------
CREATE TABLE plans (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code         text    NOT NULL UNIQUE,                            -- 'free', 'pro', 'enterprise'
    name         text    NOT NULL,
    price_cents  integer NOT NULL CHECK (price_cents >= 0),
    currency     char(3) NOT NULL DEFAULT 'EUR',
    limits       jsonb   NOT NULL DEFAULT '{}'                       -- {"seats": 10, "projects": 50}: semi-structured, rarely filtered
);

CREATE TABLE subscriptions (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    org_id               bigint NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    plan_id              bigint NOT NULL REFERENCES plans (id),
    status               text   NOT NULL CHECK (status IN ('trialing', 'active', 'past_due', 'canceled')),
    current_period_start timestamptz NOT NULL,
    current_period_end   timestamptz NOT NULL,
    canceled_at          timestamptz,
    created_at           timestamptz NOT NULL DEFAULT now(),
    CHECK (current_period_end > current_period_start),
    UNIQUE (id, org_id)
);
-- at most ONE live subscription per org, any number of historical ones
CREATE UNIQUE INDEX subscriptions_one_live_per_org
    ON subscriptions (org_id) WHERE status IN ('trialing', 'active', 'past_due');
CREATE INDEX subscriptions_plan_idx ON subscriptions (plan_id);

-- TODO 4 ---------------------------------------------------------------
CREATE TABLE invoices (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    org_id          bigint  NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    subscription_id bigint,
    number          text    NOT NULL,                                -- 'INV-2026-0001', API identifier
    status          text    NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'open', 'paid', 'void')),
    currency        char(3) NOT NULL DEFAULT 'EUR',
    total_cents     bigint  NOT NULL DEFAULT 0 CHECK (total_cents >= 0),  -- denormalized, see note below
    issued_at       timestamptz,
    due_at          timestamptz,
    paid_at         timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (org_id, number),                                         -- unique PER TENANT, also serves lookups
    UNIQUE (id, org_id),
    FOREIGN KEY (subscription_id, org_id) REFERENCES subscriptions (id, org_id),
    CHECK ((status = 'paid') = (paid_at IS NOT NULL))
);
-- Reasoning on total_cents: stored, because invoices are IMMUTABLE once issued (legal requirement) and
-- list endpoints / dashboards read the total constantly. It is written in the same transaction as the
-- items (draft invoices only) - a safe, intentional denormalization. For drafts a trigger or app code keeps it in sync.

CREATE TABLE invoice_items (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_id       bigint  NOT NULL REFERENCES invoices (id) ON DELETE CASCADE,
    description      text    NOT NULL,
    quantity         integer NOT NULL CHECK (quantity > 0),
    unit_amount_cents bigint NOT NULL CHECK (unit_amount_cents >= 0)
);
CREATE INDEX invoice_items_invoice_idx ON invoice_items (invoice_id);

-- TODO 5 ---------------------------------------------------------------
CREATE TABLE projects (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    org_id      bigint NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    name        text   NOT NULL,
    created_by  bigint NOT NULL REFERENCES users (id),
    archived_at timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX projects_name_active_uq ON projects (org_id, lower(name)) WHERE archived_at IS NULL;

-- TODO 6: remaining indexes for the API -----------------------------------
CREATE INDEX projects_created_by_idx ON projects (created_by);
-- GET /orgs/{slug}/invoices?status=open  (newest first, keyset pagination)
CREATE INDEX invoices_org_status_issued_idx ON invoices (org_id, status, issued_at DESC, id DESC);
CREATE INDEX invoices_subscription_idx ON invoices (subscription_id, org_id) WHERE subscription_id IS NOT NULL;
-- GET /orgs/{slug}/projects (newest first)
CREATE INDEX projects_org_created_idx ON projects (org_id, created_at DESC, id DESC);

-- ---------------------------------------------------------------------
-- Seed
-- ---------------------------------------------------------------------
INSERT INTO permissions (key) VALUES
    ('invoice:read'), ('invoice:write'), ('project:read'), ('project:write'), ('member:manage');
INSERT INTO plans (code, name, price_cents, limits) VALUES
    ('free', 'Free', 0, '{"seats": 3}'),
    ('pro',  'Pro',  4900, '{"seats": 25}');
