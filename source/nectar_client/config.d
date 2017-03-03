module nectar_client.config;

import inifiled;

immutable string DEFAULT_CONFIG = "
; Nectar-Client Config File\n
[network]
; The IP address which the server is running on.
ip=127.0.0.1
; The port which the server is running on.
port=8080
; If the client should connect over HTTPS (secure) or not.
useHTTPS=false
; If the client should send system information.
sendSystemData=true\n
[security]
; The location of the public ES384 key for the SERVER relative to the config directory
serverPublicKey=keys/server-pub.pem
; The location of the private and public ES384 keys for the CLIENT relative to the config directory
clientPublicKey=keys/client-pub.pem
clientPrivateKey=keys/client.pem\n
[deployment]
; If no uuid or auth string are found, attempt to register the client
; using the server's deployment API instead of exiting.
enable=false\n
";

string getConfigDirLocation(in bool useSystemDirs = false) @trusted {
	import std.file : getcwd;

	if(useSystemDirs) {
		version(Windows) {
			return "C:\\NectarClient";
		} else version(Posix) {
			return "/etc/nectar-client";
		}
	} else {
		return getcwd();
	}
}

void copyDefaultConfig(in string location) @trusted {
    import std.file : write;

    write(location, DEFAULT_CONFIG);
}

struct Configuration {
    @INI NetworkConfiguration network;
    @INI SecurityConfiguration security;
}

struct NetworkConfiguration {
    @INI string serverAddress;
    @INI ushort serverPort;

    @INI bool useSecure;
    @INI bool sendSystemData;
}

struct SecurityConfiguration {
    @INI string serverPublicKey;

    @INI string clientPublicKey;
    @INI string clientPrivateKey;
}