var mongo = require("mongodb");

mongo.MongoClient.connect("mongodb://172.17.0.2:27017/nectar", (err, db) => {
	let clients = db.collection("clients");
	console.log("connected!");
	clients.insertOne({ uuid: "e2ef4bac-fc2b-4aa7-ae20-c0f75f785a3b"}, (err2, r) => { });
	db.close();
});
