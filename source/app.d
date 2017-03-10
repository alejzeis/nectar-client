import std.stdio;

import consoled;

import nectar_client.client;
import nectar_client.util;
import nectar_client.scheduler;

void main(string[] args) @system {
	Client client = null;
	addCloseHandler((i) {
		client.stop();
	});

	bool isService = false;
	if(args.length > 1) {
		if(args[1] == "--service") {
			isService = true;
		}
	}

	client = new Client(ifUseSystemDirs(), isService);
	client.run();
}

private bool ifUseSystemDirs() @system {
	import core.stdc.stdlib : getenv;
	import std.string : toStringz, fromStringz;

	string useDirs = cast(string) fromStringz(getenv(toStringz("NECTAR_CLIENT_USE_SYSTEM")));
	if(useDirs == "true")
		return true;
	else
		return false;
}