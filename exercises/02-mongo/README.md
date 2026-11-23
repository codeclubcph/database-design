# Exercise 2 - The flexible parts of Boardly (MongoDB)

**Time: 25 min** (A: 5 min, B: 15 min, debrief: 5 min). Same pairs as Exercise 1.

In Exercise 1 you put everything that needs integrity (users, billing, roles) into PostgreSQL. Boardly also has data
that is high-volume, append-mostly, or different for every customer. The team has put it in MongoDB **quickly and
naively**. It works on a laptop and is falling over in production. Your job: find out why and fix the model.

```bash
# 1. load the (naive) data - 5,000 projects, 200,000 events, 50 tenants
docker compose exec -T mongo mongosh --quiet --file /workshop/exercises/02-mongo/seed.js

# 2. open an interactive shell and load the explain helper
docker compose exec mongo mongosh boardly
> load("/workshop/exercises/02-mongo/helpers.js")
> plan(db.events.find({ org_id: 1 }).sort({ at: -1 }).limit(50))
```

`plan(...)` prints the stages, documents examined and time. Healthy query: `docsExamined` is close to `nReturned`
and there is no `COLLSCAN` / in-memory `SORT`.

## The current shapes

```js
// events: one document per action, payload differs per type
{ org_id: 1, type: "invoice.paid", actor_id: 17, at: ISODate(...), data: { invoice_number: "INV-7", amount_cents: 4900 } }

// projects: tenant-defined custom fields as dynamic keys, comments embedded
{ _id: 1, org_id: 7, name: "Project 1", archived: false, created_at: ISODate(...),
  custom: { budget: 12000, risk: "high" },                 // each ORG has different keys!
  comments: [ { author_id: 4, body: "...", at: ISODate(...) }, ... ] }   // some projects have 3,000 of them
```

## Part A - Decide first (5 min, on paper)

For each item decide **embed**, **reference**, or **separate collection**, and say *why* in one sentence.

| Data | Your decision | Why |
|---|---|---|
| Comments of a project (0 to thousands, always read newest first) | | |
| Per-tenant custom fields (keys differ per org, must be filterable) | | |
| Activity events (append-only, 13 months of history, shown newest first) | | |
| The author's name on a comment (users live in PostgreSQL!) | | |

Rules of thumb: *embed* what you read together and what is bounded; *reference* what is unbounded, shared, or
changes on its own. Mongo's document limit is 16 MB, but the real limit is much lower - every read drags the whole document into RAM.

## Part B - Fix it (15 min)

Do the tasks in order. For each: run `plan(...)` **before**, change something, run it **after**, write down the numbers.

### B1. The activity feed (5 min)

```js
// Q1: latest 50 events of the whale tenant
plan(db.events.find({ org_id: 1 }).sort({ at: -1 }).limit(50))
// Q2: same, but only invoice.paid
plan(db.events.find({ org_id: 1, type: "invoice.paid" }).sort({ at: -1 }).limit(50))
```
Create indexes so both become `LIMIT <- FETCH <- IXSCAN` with `docsExamined: 50`.
**ESR rule:** index fields in the order **E**quality, **S**ort, **R**ange. Do you need one index or two?

### B2. Tenant-defined custom fields (5 min)

```js
// Q3: active projects of org 1 with sprint > 30
plan(db.projects.find({ org_id: 1, archived: false, "custom.sprint": { $gt: 30 } }))
```
You cannot create an index per possible key (50 tenants x 6 keys...). Use the **attribute pattern**: turn
`custom: { sprint: 31 }` into `custom_fields: [ { k: "sprint", v: 31 } ]`, put **one** compound multikey index
on `{ org_id, "custom_fields.k", "custom_fields.v" }` and query with `$elemMatch`. Write the migration with an
update pipeline (hint: `$objectToArray`, `$map`, `$unset`).

### B3. Comments (5 min)

```js
db.projects.aggregate([{ $project: { s: { $bsonSize: "$$ROOT" } } }, { $sort: { s: -1 } }, { $limit: 1 }])  // 468 KB for ONE project row
```
Move comments to their own collection (`{ project_id, org_id, author_id, body, at }`) with an index for
"newest 20 comments of project X". Hint: `$unwind` + `$merge` into `comments`. Keep a `comment_count` and the 3
most recent comments in the project (**subset pattern**) so the project list stays one cheap read.

## Stretch goals

1. **Retention:** add a TTL index so events older than 90 days vanish. **Test it on a copy of the collection** -
   most of the seed data is older than 90 days, so on `events` it would delete it. (Why is a TTL index good for
   audit logs, and when is it *not* acceptable? Compliance!)
2. **Schema validation:** add a `$jsonSchema` validator to `events` (`org_id`, `type`, `at` required) with
   `validationAction: "warn"` first. Why warn before error?
3. **Sharding thought experiment:** you need to shard `events`. Pick a shard key. (`org_id` alone -> the whale
   makes a hot shard; `{org_id, at}`? hashed `_id`?)

## Debrief (5 min)

- Which of the three fixes changed the *shape* of data, and which one only added an *index*? Which one is harder to do later with 200 M documents?
- What does Mongo give you here that PostgreSQL (with `jsonb`) would make harder? What would you lose by moving **billing** to Mongo?
- Where does the **tenant boundary** live in this model? What guarantees that a query cannot forget `org_id`?

Reference: [`solution/solution.js`](solution/solution.js)
(`docker compose exec -T mongo mongosh --quiet --file /workshop/exercises/02-mongo/solution/solution.js`).
