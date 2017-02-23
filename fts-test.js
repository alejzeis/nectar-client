var request = require("request");
var fs = require("fs");

var req = request.post("http://localhost:8080/nectar/api/v/2/3/fts/upload", (err, response, body) => {
    if(err) {
	throw err;
    }

    console.log(response.statusCode);
    console.log(body);
});

var form = req.form();
form.append('token', "eyJhbGciOiJFUzM4NCJ9.eyJleHBpcmVzIjoxODAwMDAwLCJ1dWlkIjoiNGM4NjQ4NDAtNDNlOC00YWU2LThiN2MtMjNjNTdjYjZmY2M0IiwiZnVsbCI6dHJ1ZSwidGltZXN0YW1wIjoxNDg3NTI4NTYzMDEyfQ.ZXGLzc-P21HUHL7G-X27CdWKeJlso0xaJxa6wvGgfeRE8ywUoIEhTxxuk4kdrXq6YG5bC7MhcIn9gVjHTFtMrm2zj7HMfqcbIes_AP8Q2aYjx843P25SzDB0VNJBSPW_");
form.append('path', "");
form.append('name', "test.txt");
form.append('public', "false");
form.append('file', fs.createReadStream("test.txt"));

