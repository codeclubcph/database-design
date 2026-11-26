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

## Detailed walkthrough and common errors

### Start MongoDB and the seed

Start the database and verify it:

```bash
docker compose up -d mongo
docker compose exec mongo mongosh boardly --eval 'db.runCommand({ping:1})'
```

Load the deterministic seed from the repository mount:

```bash
docker compose exec -T mongo mongosh --quiet \
  --file /workshop/exercises/02-mongo/seed.js
```

The seed drops the complete `boardly` database first. Do not run it against a real database or use it as a
migration for user data. It should report `5000` projects and `200000` events. Re-running it is safe and restores
the original shape.

Open the interactive shell and load the plan helper:

```bash
docker compose exec mongo mongosh boardly
load("/workshop/exercises/02-mongo/helpers.js")
```

A `COLLSCAN` means MongoDB read every document in the collection. A healthy limited feed should use `IXSCAN` and
return approximately the same number of examined documents and returned documents.

### B1 - activity feed procedure

Measure both queries before adding indexes:

```javascript
plan(db.events.find({ org_id: 1 }).sort({ at: -1 }).limit(50));
plan(db.events.find({ org_id: 1, type: "invoice.paid" }).sort({ at: -1 }).limit(50));
```

Create one index for the general feed and one for the type filter:

```javascript
db.events.createIndex({ org_id: 1, at: -1 });
db.events.createIndex({ org_id: 1, type: 1, at: -1 });
```

The second index follows ESR: equality on `org_id`, equality on `type`, then sort on `at`. Record
`nReturned`, `totalDocsExamined`, and `executionTimeMillis` after rebuilding or warming the queries.

Do not expect one compound index to serve every arbitrary sort. An index on `{ at: -1, org_id: 1 }` cannot efficiently
serve the equality-on-org filter because the sort field comes first.

### B2 - custom fields migration procedure

First prove the baseline problem:

```javascript
plan(db.projects.find({
  org_id: 1,
  archived: false,
  "custom.sprint": { $gt: 30 }
}));
```

Preview the migration on one document before applying it to all documents:

```javascript
db.projects.findOne({}, { custom: 1 });
```

Run the update pipeline:

```javascript
db.projects.updateMany({}, [
  {
    $set: {
      custom_fields: {
        $map: {
          input: { $objectToArray: "$custom" },
          as: "f",
          in: { k: "$$f.k", v: "$$f.v" }
        }
      }
    }
  },
  { $unset: "custom" }
]);
```

Create one multikey index:

```javascript
db.projects.createIndex({
  org_id: 1,
  "custom_fields.k": 1,
  "custom_fields.v": 1
});
```

Verify the new shape:

```javascript
db.projects.findOne({}, { custom: 0 });
```

The query must use `$elemMatch` so the key and value come from the same array element:

```javascript
plan(db.projects.find({
  org_id: 1,
  archived: false,
  custom_fields: {
    $elemMatch: { k: "sprint", v: { $gt: 30 } }
  }
}));
```

Avoid a separate array element for key and value; `k: "sprint", v: 31` must describe the same object.

### B3 - comments migration procedure

Measure the largest document:

```javascript
db.projects.aggregate([
  { $project: { s: { $bsonSize: "$$ROOT" } } },
  { $sort: { s: -1 } },
  { $limit: 1 }
]).toArray();
```

Move only projects with at least one comment. The seed contains one project with 3000 comments, plus small arrays:

```javascript
db.projects.aggregate([
  { $match: { "comments.0": { $exists: true } } },
  { $unwind: "$comments" },
  {
    $project: {
      _id: 0,
      project_id: "$_id",
      org_id: 1,
      author_id: "$comments.author_id",
      body: "$comments.body",
      at: "$comments.at"
    }
  },
  { $merge: { into: "comments" } }
]);
```

Keep recent comments and the count on the project:

```javascript
db.projects.updateMany({}, [
  {
    $set: {
      comment_count: { $size: "$comments" },
      recent_comments: { $slice: ["$comments", -3] }
    }
  },
  { $unset: "comments" }
]);
```

Create newest-first indexes:

```javascript
db.comments.createIndex({ project_id: 1, at: -1 });
db.projects.createIndex({ org_id: 1, archived: 1, created_at: -1 });
```

Verify:

```javascript
plan(db.comments.find({ project_id: 1 }).sort({ at: -1 }).limit(20));
db.projects.findOne({ _id: 1 }, { comments: 1, recent_comments: 1, comment_count: 1 });
```

The old `comments` field should be absent, but `recent_comments` and `comment_count` should remain.

### Common MongoDB error messages

| Error or symptom | Likely cause | Fix |
|---|---|---|
| `MongoServerError: database boardly not found` or empty collections | Seed was not loaded, or a different `mongosh` database was opened | Run `seed.js`, then use `mongosh boardly` |
| Seed reports fewer than 5000 projects | A previous file failed mid-write or another JavaScript process changed the database | Re-run `seed.js`; it intentionally drops `boardly` |
| `COLLSCAN` | There is no matching index or the index shape does not match the equality/sort pattern | Add the ESR index and rerun `plan(...)` |
| `SORT` stage still appears | Sort field, sort direction, or equality fields differ from the index | Inspect `db.events.getIndexes()` and match `{ org_id, at }` |
| `$objectToArray requires an object` | A document has `custom: null` or a scalar value | Filter or normalize invalid `custom` values before migration |
| `$size requires an array` | `comments` is missing or has already been removed | Match only documents with `comments.0`, or rerun seed and then migration |
| `$merge: Cannot insert document` | The target collection requires unique fields or is not writable | Check collection validation and remove stale target data |
| `plan is not defined` | The helper was not loaded in this shell | Run `load("/workshop/exercises/02-mongo/helpers.js")` |
| `E11000 duplicate key` | A unique index conflicts with existing duplicate data | Clean or migrate duplicates before creating uniqueness |
| `documentsExamined` equals 5000 or 200000 | Query was unindexed or too broad | Confirm tenant equality and matching ESR index |
| One project is much larger than 16 MB | Embedded comment growth was not bounded | Move unbounded comments to a separate collection |
| A sprint query still uses `custom.sprint` | Migration was applied only in memory or the old seed was restored | Query `custom_fields` and `$elemMatch` and verify `custom` is removed |
| TTL deletes too many records | The seed's events are old, or retention requirements are unknown | Test TTL only on `events_ttl_demo`, never a compliance collection |

Run the complete reference implementation only after completing the tasks yourself:

```bash
docker compose exec -T mongo mongosh --quiet \
  --file /workshop/exercises/02-mongo/solution/solution.js
```

Reference: [`solution/solution.js`](solution/solution.js).
