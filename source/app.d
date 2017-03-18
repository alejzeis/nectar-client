import std.stdio;

import consoled;

import nectar_client.client;
import nectar_client.util;
import nectar_client.scheduler;
import nectar_client.service;

void main(string[] args) @system {
	Client client = null;
	addCloseHandler((i) {
		client.stop();
	});

	bool isService = false;
	if(args.length > 1) {
		if(args[1] == "--service") {
			isService = true;
		} else if(args[1] == "--winservice"){
			runWindowsServiceWatcher();
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

private void runWindowsServiceWatcher() @system {
	import core.stdc.stdlib : exit;
	import core.thread;
	
	import std.concurrency;
	import std.datetime;
	import std.process;
	import std.string;
	
	import std.file : remove, rename;
	
	version(Windows) {
		bool signaledTerminate = false;
		//Pid pid;
		ProcessPipes pipes;
		while(true) {
			//toFile("", getTempDirectoryPath() ~ "//nectar-client-winservice-stdin.txt");
		
			//File stdout = createNewTmpSTDIOFile("nectar-client-winservice-stdout.txt");
			//File stdin = createNewTmpSTDIOFile("nectar-client-winservice-stdin.txt", "r");
			
			//pid = spawnProcess(["C:\\NectarClient\\nectar-client.exe", "--service"], stdin, stdout);
			pipes = pipeProcess(["C:\\NectarClient\\nectar-client.exe", "--service"], Redirect.stdin | Redirect.stdout);

			writeln("STARTED");
			
			auto serviceTid = spawn(&consoleListenThread); // Spawn listening thread to listen for input from windows service

			while(true) {
				auto status = tryWait(pipes.pid);
				if(status.terminated && !signaledTerminate) {
					if(checkUpdateExecutable()) { // Check if a new executable has been found
						writeln("UPDATEEXEC"); // Write out anyway, but C# can't read our output (no idea why)
						
						remove("C:\\NectarClient\\nectar-client.exe");
						rename(getNewExecutablePath(ifUseSystemDirs()) ~ PATH_SEPARATOR ~ "nectar-client-exec-new.bin", "C:\\NectarClient\\nectar-client.exe");
					}
					pipes = pipeProcess(["C:\\NectarClient\\nectar-client.exe", "--service"], Redirect.stdin);
					writeln("RESTARTED");
					// Restart process
				}
				
				receiveTimeout(100.msecs, (string message) {
					message = message.strip();
					if(message.startsWith("!")) { // Check if message is from nectar-client
						writeln(message);
						return;
					}

					// message is from windows service

                    if(message == "POWER-SUSPEND" || message == "SERVICESTOP") {
						signaledTerminate = true;
					}
					//toFile(message, stdin.name);
					pipes.stdin.writeln(message);
					pipes.stdin.flush();
					if(signaledTerminate) {
						Thread.sleep(3000.msecs);
						if(!tryWait(pipes.pid).terminated) {
							kill(pipes.pid);
							writeln("KILLED");
							exit(2);
						} else {
							exit(0);
						}
					}
                });
			}
		}
	} else {
		writeln("Can't run as windows service watcher on a non-windows operating system!");
		exit(1);
	}
}

version(Windows) {
	import std.file : exists;
	
	import nectar_client.util : getNewExecutablePath, PATH_SEPARATOR;
	
	private bool checkUpdateExecutable() @system {
		if(exists(getNewExecutablePath(ifUseSystemDirs()) ~ PATH_SEPARATOR ~ "nectar-client-exec-new.bin")) {
			return true;
		} else {
			return false;
		}
	}
}