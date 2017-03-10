module nectar_client.util;

import std.conv : to;
import std.json;

version(Windows) {
	immutable string PATH_SEPARATOR = "\\";
} else {
	immutable string PATH_SEPARATOR = "/";
}

enum ClientState {
	ONLINE = 0,
	SHUTDOWN = 1,
	SLEEP = 2,
	RESTART = 3,
	UNKNOWN = 4
}

static ClientState fromInt(int state) @safe {
	switch(state) {
		case 0:
			return ClientState.ONLINE;
		case 1:
			return ClientState.SHUTDOWN;
		case 2:
			return ClientState.SLEEP;
		case 3:
			return ClientState.RESTART;
		default:
			throw new Exception("State is invalid.");
	}
}

/**
 * Get the current time in milliseconds (since epoch).
 * This method uses bindings to the C functions gettimeofday and
 * GetSystemTime depending on the platform.
 */
long getTimeMillis() @system nothrow {
	version(Posix) {
		pragma(msg, "Using core.sys.posix.sys.time.gettimeofday() for getTimeMillis()");
		import core.sys.posix.sys.time;

		timeval t;
		gettimeofday(&t, null);
		
		return (t.tv_sec) * 1000 + (t.tv_usec) / 1000;
	} else version(Windows) {
		pragma(msg, "Using core.sys.windows.winbase.GetSystemTime() for getTimeMillis()");
		import core.sys.windows.winbase : SYSTEMTIME, GetSystemTime;
		
		SYSTEMTIME time;
		GetSystemTime(&time);
		
		return (time.wSecond * 1000) + time.wMilliseconds;
	} else {
		pragma(msg, "Need to implement getTimeMillis() for this platform!");
	}
}

JSONValue getUpdatesInfo() {
	import std.stdio : File;
	import std.file : readText;
	import std.string;
	import std.process;

	JSONValue root = JSONValue();

	version(linux) {
		File tmpOut = createNewTmpSTDIOFile("nectar-client-apt-check-output.txt");

		try {
			auto pid = spawnProcess(["/usr/lib/update-notifier/apt-check"], std.stdio.stdin, tmpOut, tmpOut);

			if(wait(pid) != 0) {
				// Process exited with non-zero exit code, set to unknown.
				root["securityUpdates"] = -1;
				root["otherUpdates"] = -1;
			} else {
				tmpOut.close();
				string[] exploded = readText(tmpOut.name).split(";");
				root["securityUpdates"] = to!int(exploded[0]);
				root["otherUpdates"] = to!int(exploded[1]);
			}
		} catch(ProcessException e) {
			// Failed to get the update count, set to unknown then.
			root["securityUpdates"] = -1;
			root["otherUpdates"] = -1;	
		}
	} else {
		pragma(msg, "WARN: getUpdatesInfo() only supports Linux currently.");

		root["securityUpdates"] = -1;
		root["otherUpdates"] = -1;
	}

	return root;
}

std.stdio.File createNewTmpSTDIOFile(in string name) @system {
	import std.stdio : File;

	return File(getTempDirectoryPath() ~ PATH_SEPARATOR ~ name, "w");
}

string getTempDirectoryPath() @system {
	version(Posix) {
		import core.stdc.stdlib : getenv;
		import std.string: toStringz, fromStringz;

		auto env = fromStringz(getenv(toStringz("TMPDIR")));
		if(env == "") {
			return "/tmp";
		} else return cast(string) env;
	} else version(Windows) {
		import core.sys.windows.winbase : GetTempPath, DWORD;
		
		void[] data = new void[256];
		DWORD length = GetTempPath(256, data);
		return cast(string) fromStringz(cast(char[]) data[0..length]);
	} else {
		pragma(msg, "WARN: Need to implement getTempDirectoryPath() correctly for this operating system.");
		
		return "tmp"; // From current directory
	}
}

// THE FOLLOWING CODE IS FROM THE JWTD PROJECT, UNDER THE MIT LICENSE
// You can find the original project and code here: https://github.com/olehlong/jwtd

/**
 * Encode a string with URL-safe Base64.
 */
string urlsafeB64Encode(string inp) pure nothrow {
	import std.base64 : Base64URL;
	import std.string : indexOf;

	auto enc = Base64URL.encode(cast(ubyte[])inp);
	auto idx = enc.indexOf('=');
	return cast(string)enc[0..idx > 0 ? idx : $];
}

/**
 * Decode a string with URL-safe Base64.
 */
string urlsafeB64Decode(string inp) pure {
	import std.base64 : Base64URL;
	import std.array : replicate;

	int remainder = inp.length % 4;
	if(remainder > 0) {
		int padlen = 4 - remainder;
		inp ~= replicate("=", padlen);
	}
	return cast(string)(Base64URL.decode(cast(ubyte[])inp));
}

// END JWTD

bool jsonValueToBool(std.json.JSONValue value) {
	import std.json : JSON_TYPE;

	switch(value.type) {
		case JSON_TYPE.TRUE:
			return true;
		case JSON_TYPE.FALSE:
			return false;
		default:
			throw new Exception("Value is not a boolean!");
	}
}

import std.net.curl;

template RequestErrorHandleMixin(string operation, int[] expectedStatusCodes, bool fatal, bool doReturn = false) {
	const char[] RequestErrorHandleMixin = 
	"
	bool failure = false;

	if(!(ce is null) && !canFind(ce.toString(), \"request returned status code\")) {
		logger.error(\"Failed to connect to \" ~ url ~ \", CurlException.\");
		logger.trace(ce.toString());
		logger." ~ (fatal ? "fatal" : "error") ~ "(\"Failed to process " ~ operation ~ "!\");
		failure = true;
		" ~ (doReturn ? "return;" : "") ~ "
	}

	if(!canFind(" ~ to!string(expectedStatusCodes) ~ ", status)) {
		logger.error(\"Failed to connect to \" ~ url ~ \", server returned non-expected status code. (\" ~ to!string(status) ~ \")\");
		logger." ~ (fatal ? "fatal" : "error") ~ "(\"Failed to process " ~ operation ~ "!\");
		failure = true;
		" ~ (doReturn ? "return;" : "") ~ "
	}
	";
}

void issueGETRequest(in string url, void delegate(ushort status, string content, CurlException err) callback) {

	string content;

	auto request = HTTP(url);
	try {
		content = cast(string) get(url, request);
	} catch(CurlException e) {
		callback(request.statusLine().code, content, e);
		return;
	}

	callback(request.statusLine().code, content, null);
}