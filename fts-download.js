var request = require("request");
var fs = require("fs");

let token = "eyJhbGciOiJFUzM4NCJ9.eyJleHBpcmVzIjoxODAwMDAwLCJ1dWlkIjoiNGM4NjQ4NDAtNDNlOC00YWU2LThiN2MtMjNjNTdjYjZmY2M0IiwiZnVsbCI6dHJ1ZSwidGltZXN0YW1wIjoxNDg3NDgxOTY3Mzc3fQ.0naoU89AbELDg_517_w25PVoktWORj6P5ebvwGDENWoA87MECmFTarwQfnMGygXJS-NJ53tXeGLEK50cazwELmTDoe7xM0tKITrMmTCPVBio49YBKrU3CddmV_bYssrP";

request("http://localhost:8080/nectar/api/v/2/3/fts/download?token=" + token + "&public=true&path=tes1t.txt", (err, response, body) => {
    console.log(err);
    console.log(response.statusCode);
    console.log(body);
});
