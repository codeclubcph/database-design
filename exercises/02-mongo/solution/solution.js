// Exercise 2 - reference solution.  Run AFTER seed.js:
//   docker compose exec -T mongo mongosh --quiet --file /workshop/exercises/02-mongo/solution/solution.js
load("/workshop/exercises/02-mongo/helpers.js");
const b = db.getSiblingDB("boardly");
db = b;

print("\n=== BEFORE ===");
print("-- Q1 feed");        plan(db.events.find({ org_id: 1 }).sort({ at: -1 }).limit(50));
print("-- Q2 feed by type"); plan(db.events.find({ org_id: 1, type: "invoice.paid" }).sort({ at: -1 }).limit(50));
print("-- Q3 custom field"); plan(db.projects.find({ org_id: 1, archived: false, "custom.sprint": { $gt: 30 } }));
print("-- Q4 project list size: biggest doc bytes =",
  db.projects.aggregate([{ $project: { s: { $bsonSize: "$$ROOT" } } }, { $sort: { s: -1 } }, { $limit: 1 }]).toArray()[0].s);

// ---- 1. Events: ESR rule (Equality, Sort, Range) ----------------------------------------
db.events.createIndex({ org_id: 1, at: -1 });                 // Q1
db.events.createIndex({ org_id: 1, type: 1, at: -1 });        // Q2: equality, equality, sort
db.events.createIndex({ org_id: 1, "data.project_id": 1, at: -1 }, { partialFilterExpression: { "data.project_id": { $exists: true } } }); // "history of project X"

// ---- 2. Projects: attribute pattern for tenant-defined custom fields ---------------------
db.projects.updateMany({}, [
  { $set: { custom_fields: { $map: { input: { $objectToArray: "$custom" }, as: "f", in: { k: "$$f.k", v: "$$f.v" } } } } },
  { $unset: "custom" },
]);
// ONE index covers every custom field of every tenant (vs. one index per possible key)
db.projects.createIndex({ org_id: 1, "custom_fields.k": 1, "custom_fields.v": 1 });

// ---- 3. Comments: unbounded array -> own collection + subset pattern ---------------------
db.projects.aggregate([
  { $match: { "comments.0": { $exists: true } } },
  { $unwind: "$comments" },
  { $project: { _id: 0, project_id: "$_id", org_id: 1, author_id: "$comments.author_id", body: "$comments.body", at: "$comments.at" } },
  { $merge: { into: "comments" } },
]);
db.projects.updateMany({}, [
  { $set: { comment_count: { $size: "$comments" }, recent_comments: { $slice: ["$comments", -3] } } },
  { $unset: "comments" },
]);
db.comments.createIndex({ project_id: 1, at: -1 });
db.projects.createIndex({ org_id: 1, archived: 1, created_at: -1 });

// ---- 4. Guard rails: schema validation (warn first, then error) --------------------------
db.runCommand({
  collMod: "events",
  validator: { $jsonSchema: { bsonType: "object", required: ["org_id", "type", "at"],
    properties: { org_id: { bsonType: "number" }, type: { bsonType: "string", pattern: "^[a-z_]+\\.[a-z_]+$" }, at: { bsonType: "date" } } } },
  validationLevel: "moderate", validationAction: "warn",
});

// ---- 5. Retention: TTL index (shown on a COPY - on `events` it would delete 75% of the demo data!) ----
db.events.aggregate([{ $match: { at: { $gte: new Date("2026-01-01") } } }, { $out: "events_ttl_demo" }]);
db.events_ttl_demo.createIndex({ at: 1 }, { expireAfterSeconds: 90 * 86400 });

print("\n=== AFTER ===");
print("-- Q1 feed");        plan(db.events.find({ org_id: 1 }).sort({ at: -1 }).limit(50));
print("-- Q2 feed by type"); plan(db.events.find({ org_id: 1, type: "invoice.paid" }).sort({ at: -1 }).limit(50));
print("-- Q3 custom field"); plan(db.projects.find({ org_id: 1, archived: false, custom_fields: { $elemMatch: { k: "sprint", v: { $gt: 30 } } } }));
print("-- Q4 biggest project doc bytes =",
  db.projects.aggregate([{ $project: { s: { $bsonSize: "$$ROOT" } } }, { $sort: { s: -1 } }, { $limit: 1 }]).toArray()[0].s);
print("-- comments of project 1, newest 20"); plan(db.comments.find({ project_id: 1 }).sort({ at: -1 }).limit(20));
