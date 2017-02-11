const mongo = require("mongodb");
const uuidV4 = require("uuid/v4");
const crypto = require("crypto");

function doHash(input) {
    return crypto.createHash("sha256").update(input).digest("base64");
}

var ip;

if(!process.argv[2]) {
    console.log("Usage: node setup-test-env.js [ip:port]");
    process.exit(1);
} else {
    ip = process.argv[2];
}

let clientUUID = uuidV4();
let authStr = uuidV4(); // Nectar-Server will generate a more secure string, but for testing a UUID will be fine.

console.log("Adding test client.");
console.log("Admin user: username: admin, password: admin");

mongo.MongoClient.connect("mongodb://" + ip + "/nectar", (err, db) => {
    if(err) {
        console.log(err);
        process.exit(1);
    }

	let clients = db.collection("clients");
    let users = db.collection("users");

    console.log("- Connected!");

	clients.insertOne({ uuid: clientUUID, auth: doHash(authStr) }, (err2, r) => {
        if(err2) {
            console.log(err2);
            process.exit(1);
        }
    });

    users.insertOne({ username: "admin", password: doHash("admin"), admin: true }, (err3, r2) => {
        if(err3) {
            console.log(err3);
            process.exit(1);
        }
    });

	db.close();

    console.log("Done.");
});
