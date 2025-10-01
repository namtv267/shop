db.createUser({
    user: "order",
    pwd: "pass",
    roles: [{role: "readWrite", db: "orderdb"}]
})