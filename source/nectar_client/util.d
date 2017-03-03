module nectar_client.util;

version(Windows) {
	immutable string PATH_SEPARATOR = "\\";
} else {
	immutable string PATH_SEPARATOR = "/";
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

import std.net.curl;

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