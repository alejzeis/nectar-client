module nectar_client.service;

import std.stdio;
import std.concurrency;

import core.thread;

/++
    Thread which listens for input from the terminal and passes it
    to the main Client thread. Used when the client is in Service mode,
    as the main Service program will communicate via STDIN and STDOUT, rather
    than Unix or TCP sockets.
+/
void consoleListenThread() {
    Thread.getThis().isDaemon = true; // If the main thread exits, then we do too.

    string line;
    while((line = readln()) !is null) {
        ownerTid.send(line);
    }
}