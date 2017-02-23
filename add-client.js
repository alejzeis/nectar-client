var mongo = require("mongodb");

if(!process.argv[2]) {
    console.log("Usage: node add-client.js [uuid]");
    process.exit(1);
}

mongo.MongoClient.connect("mongodb://172.17.0.2:27017/nectar", (err, db) => {
	let clients = db.collection("clients");
	console.log("connected!");
	clients.insertOne({ uuid: process.argv[2]}, (err2, r) => { });
	db.close();
});
