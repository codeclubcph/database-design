// Load inside mongosh:   load("/workshop/exercises/02-mongo/helpers.js")
// Usage:                 plan(db.events.find({ org_id: 1 }).sort({ at: -1 }).limit(50))
// Prints the plan stages, how many index keys / documents were examined, and the time.
// Rule of thumb: docsExamined should be close to nReturned. COLLSCAN on a big collection = missing index.
function plan(cursor) {
  const e = cursor.explain("executionStats");
  let wp = e.queryPlanner.winningPlan;
  if (wp.queryPlan) wp = wp.queryPlan;               // newer servers wrap the plan
  const stages = [];
  (function walk(n) {
    if (!n) return;
    stages.push(n.stage + (n.indexName ? "(" + n.indexName + ")" : ""));
    if (n.inputStage) walk(n.inputStage);
    (n.inputStages || []).forEach(walk);
  })(wp);
  const s = e.executionStats;
  print("stages        : " + stages.join(" <- "));
  print("nReturned     : " + s.nReturned);
  print("keysExamined  : " + s.totalKeysExamined);
  print("docsExamined  : " + s.totalDocsExamined);
  print("time (ms)     : " + s.executionTimeMillis);
}
