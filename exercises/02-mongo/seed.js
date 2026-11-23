// Exercise 2 - seed data in a deliberately NAIVE shape.
//   docker compose exec -T mongo mongosh --quiet --file /workshop/exercises/02-mongo/seed.js
// Database: boardly.   Safe to re-run (drops the database first).
// Takes ~15 s.  Deterministic: everybody gets the same data.

const dbx = db.getSiblingDB("boardly");
dbx.dropDatabase();

// tiny deterministic PRNG (mulberry32) so the data is identical on every laptop
let _s = 42;
function rnd() {
  _s |= 0; _s = (_s + 0x6d2b79f5) | 0;
  let t = Math.imul(_s ^ (_s >>> 15), 1 | _s);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const pick = (a) => a[Math.floor(rnd() * a.length)];
const int = (lo, hi) => lo + Math.floor(rnd() * (hi - lo + 1));

const NOW = new Date("2026-11-22T12:00:00Z").getTime();
const DAY = 86400000;

// Each organisation defines its OWN custom fields on projects (this is why we are in Mongo-land).
const ORGS = 50;
const fieldCatalog = [
  ["budget", () => int(1000, 90000)],
  ["risk", () => pick(["low", "medium", "high"])],
  ["client", () => pick(["Initech", "Hooli", "Umbrella", "Stark", "Wayne"])],
  ["sprint", () => int(1, 40)],
  ["billable", () => rnd() < 0.7],
  ["region", () => pick(["EU", "US", "APAC"])],
];
const orgFields = [];
for (let o = 1; o <= ORGS; o++) {
  const n = int(2, 4);
  orgFields[o] = [...fieldCatalog].sort(() => rnd() - 0.5).slice(0, n);
}

// ---- projects (custom fields as dynamic keys; comments embedded in an array) ----
const projects = [];
for (let i = 1; i <= 5000; i++) {
  const org = int(1, ORGS);
  const custom = {};
  for (const [k, gen] of orgFields[org]) custom[k] = gen();
  const hot = i <= 5;                      // 5 "hot" projects with thousands of comments
  const nComments = hot ? 3000 : int(0, 4);
  const comments = [];
  for (let c = 0; c < nComments; c++) {
    comments.push({
      author_id: int(1, 200),
      body: "Comment " + c + " " + "lorem ipsum dolor sit amet ".repeat(int(1, 6)),
      at: new Date(NOW - int(1, 400) * DAY),
    });
  }
  projects.push({
    _id: i, org_id: org, name: "Project " + i, created_by: int(1, 200),
    archived: rnd() < 0.1, created_at: new Date(NOW - int(1, 700) * DAY),
    custom, comments,
  });
}
dbx.projects.insertMany(projects);

// ---- events: one document per action, payload differs per type ----
const types = {
  "project.created":  () => ({ project_id: int(1, 5000), name: "Project " + int(1, 5000) }),
  "member.invited":   () => ({ email: "user" + int(1, 9999) + "@example.com", role: pick(["admin", "member"]) }),
  "invoice.paid":     () => ({ invoice_number: "INV-" + int(1, 99999), amount_cents: int(1000, 99000), currency: "EUR" }),
  "comment.added":    () => ({ project_id: int(1, 5000), comment_len: int(5, 500) }),
  "plan.changed":     () => ({ from: pick(["free", "pro"]), to: pick(["pro", "enterprise"]) }),
};
const typeNames = Object.keys(types);
let batch = [];
for (let i = 1; i <= 200000; i++) {
  const type = pick(typeNames);
  const org = rnd() < 0.2 ? 1 : int(2, ORGS);        // org 1 is the noisy whale
  batch.push({
    org_id: org, type, actor_id: int(1, 200),
    at: new Date(NOW - Math.floor(rnd() * 400 * DAY)),    // ~13 months of history
    data: types[type](),
  });
  if (batch.length === 5000) { dbx.events.insertMany(batch); batch = []; }
}
if (batch.length) dbx.events.insertMany(batch);

print("projects:", dbx.projects.countDocuments(), " events:", dbx.events.countDocuments());
print("biggest project doc (bytes):", dbx.projects.aggregate([{ $project: { s: { $bsonSize: "$$ROOT" } } }, { $sort: { s: -1 } }, { $limit: 1 }]).toArray()[0].s);
print("org 1 custom fields:", Object.keys(orgFields[1].reduce((a, [k]) => (a[k] = 1, a), {})).join(", "));
