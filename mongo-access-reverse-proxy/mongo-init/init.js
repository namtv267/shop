// /docker-entrypoint-initdb.d/init.js
const dbName = "sally";
const collName = "service";

const conn = new Mongo();
const db = conn.getDB(dbName);

// Xóa nếu đã tồn tại (đảm bảo idempotent khi dev)
if (db.getCollectionNames().includes(collName)) {
  db[collName].drop();
}

const docs = [];
for (let i = 1; i <= 100; i++) {
  docs.push({
    _id: i,
    servey_name: "name" + i
  });
}

db.createCollection(collName);
db[collName].insertMany(docs);

print(`Initialized db '${dbName}', collection '${collName}' with ${docs.length} docs.`);
