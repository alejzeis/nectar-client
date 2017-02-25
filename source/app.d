import std.stdio;
import std.file;

import jwtd.jwt;

void main() {
	string token = "eyJhbGciOiJFUzM4NCJ9.eyJoYXNoIjoiOGYwOGU1YjQzNTU1NjMxZTcyOThkMTM2ZjI3MjMzNWFkNWI0NDIxMzVjOTZhOTI3NTMwZjM0ZmE4ZDM4MmU1YyIsInRpbWVzdGFtcCI6MTQ4NzcyODIzMzIxNX0.ilQLA-7RSv1TqXVW_PfPIwxmEDoFjfrSPjqKvw7mqFrY8S14ixLd2qi39p7j_oTLMcFFs4DHqWQJP4oR00nS2l82ZPwSNPJaYik4uWr5LrA9a4jHH9WyxSAYSO5MnykV";

	writeln(token);
	writeln(decode(token, readPubKey()));
}

string readPubKey() {
	return readText("server-pub.pem");
}

string readPrivateKey() {
	return readText("server.pem");
}
