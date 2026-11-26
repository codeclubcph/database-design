# PostgreSQL cheat sheet for Exercise 1

SQL has a lot of new vocabulary. This guide explains the commands and keywords used when designing and querying
the Boardly database. The examples illustrate the syntax; they are not the complete exercise schema.

## Creating a table

```sql
CREATE TABLE organizations (
    id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL
);
```

| Keyword | Meaning |
|---|---|
| `CREATE TABLE` | Create a new table. |
| `bigint` | A whole number, such as `1` or `42`. |
| `text` | Text, such as `'Acme'`. SQL string values use single quotes. |
| `GENERATED ALWAYS AS IDENTITY` | PostgreSQL generates a value for this column when you insert a row. |
| `PRIMARY KEY` | Identifies each row uniquely. It cannot be null. |
| `NOT NULL` | A value is required; it cannot be null. |

## Linking tables with `REFERENCES`

```sql
CREATE TABLE roles (
    id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    org_id bigint NOT NULL REFERENCES organizations (id),
    name   text NOT NULL
);
```

`REFERENCES organizations (id)` means that each `org_id` value must already exist in `organizations.id`. For
example, if Acme has `id = 1`, a role with `org_id = 1` belongs to Acme. PostgreSQL rejects an `org_id` that
does not match an existing organization.

This relationship is called a **foreign key**. You can draw a line from the foreign key to the referenced key:

```text
roles                           organizations
-----                           -------------
FK org_id --------------------> PK id
   name                            name
```

You can also declare the same single-column foreign key separately:

```sql
CREATE TABLE roles (
    id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    org_id bigint NOT NULL,
    name   text NOT NULL,
    FOREIGN KEY (org_id) REFERENCES organizations (id)
);
```

## Rules for values

```sql
CREATE TABLE example_membership_statuses (
    id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    label  text NOT NULL UNIQUE,
    status text NOT NULL DEFAULT 'invited'
           CHECK (status IN ('invited', 'active', 'suspended'))
);
```

| Keyword | Meaning |
|---|---|
| `UNIQUE` | Prevents duplicate non-null values in the column. |
| `DEFAULT` | Uses this value when an insert omits the column. |
| `CHECK` | Rejects a row when the condition is false. Use `NOT NULL` as well when a value is required. |
| `IN (...)` | Matches one of the listed values. |
| `NULL` | Represents a missing or unknown value; it is not the same as an empty string. |

## Keys made from two columns

Sometimes a **combination** of columns identifies a row:

```sql
CREATE TABLE memberships (
    org_id  bigint NOT NULL REFERENCES organizations (id),
    user_id bigint NOT NULL REFERENCES users (id),
    PRIMARY KEY (org_id, user_id)
);
```

This example assumes the `organizations` and `users` tables already exist. The primary key prevents the same user
from having two membership rows in the same organization. That user can still have a membership in another
organization.

For the exercise, each membership also needs a required `role_id`. A foreign key to `roles.id` alone does not
prevent a membership from using another organization's role. A **composite foreign key** checks both values
together:

```sql
-- In roles: make the pair a valid foreign-key target.
UNIQUE (id, org_id)

-- In memberships: the exact pair must exist in roles.
FOREIGN KEY (role_id, org_id) REFERENCES roles (id, org_id)
```

These are table constraints to put inside their respective `CREATE TABLE` statements, not standalone commands.
The referenced pair must have a matching `UNIQUE` or primary-key constraint.

## Reading and writing data

| Command | What it does | Example |
|---|---|---|
| `INSERT INTO` | Add a row | `INSERT INTO organizations (name) VALUES ('Acme');` |
| `SELECT ... FROM` | Read rows | `SELECT id, name FROM organizations;` |
| `WHERE` | Filter rows | `SELECT * FROM organizations WHERE id = 1;` |
| `UPDATE ... SET` | Change rows | `UPDATE organizations SET name = 'New name' WHERE id = 1;` |
| `DELETE FROM` | Remove rows | `DELETE FROM organizations WHERE id = 1;` |
| `JOIN ... ON` | Combine related rows | `SELECT * FROM memberships JOIN organizations ON memberships.org_id = organizations.id;` |

**Be careful:** `UPDATE` or `DELETE` without a `WHERE` clause affects every row in the table.

## Useful `psql` shortcuts

These are PostgreSQL terminal commands, not SQL keywords:

```text
\dt                  list tables in the current search path
\d memberships       show a table's columns, keys, and constraints
\q                   quit
```

If you created your tables in the `app` schema, run `SET search_path = app;` before using the examples or `\dt`.
After trying the exercise, compare your work with the [reference schema](solution/schema.sql).
