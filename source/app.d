import std.stdio;

import consoled;

import nectar_client.client;
import nectar_client.util;
import nectar_client.scheduler;

void main() {
	Client client = null;
	addCloseHandler((i) {
		client.stop();
	});

	client = new Client(ifUseSystemDirs());
	client.scheduler.registerTask(Task.constructRepeatingTask(() {
		import std.conv;
		client.logger.info("Testing task at " ~ to!string(getTimeMillis()));
	}, 1000));
	client.run();
}

private bool ifUseSystemDirs() {
	import core.stdc.stdlib : getenv;
	import std.string : toStringz, fromStringz;

	string useDirs = cast(string) fromStringz(getenv(toStringz("NECTAR_CLIENT_USE_SYSTEM")));
	if(useDirs == "true")
		return true;
	else
		return false;
}