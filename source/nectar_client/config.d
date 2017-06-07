module nectar_client.config;

import std.exception : enforce;
import std.json;
import std.conv;

import nectar_client.util;

immutable string DEFAULT_CONFIG = "{
    \"network\" : {
        \"ip\": \"127.0.0.1\",
        \"port\": 8080,
        \"useHTTPS\": false
    },
    \"security\" : {
        \"serverPublicKey\": \"keys/server-pub.pem\",
        \"clientPublicKey\": \"keys/client-pub.pem\",
        \"clientPrivateKey\": \"keys/client.pem\"
    },
    \"deployment\" : {
        \"enable\": false
    }
}
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

string getLogLocation(in bool useSystemDirs = false) @trusted {
    import std.file : getcwd;

    if(useSystemDirs) {
        version(Windows) {
            return "C:\\NectarClient\\client.log";
        } else version(Posix) {
            return "/var/log/nectar-client.log";
        }
    } else {
        return getcwd() ~ PATH_SEPARATOR ~ "client.log";
    }
}

void copyDefaultConfig(in string location) @trusted {
    import std.file : write;

    write(location, DEFAULT_CONFIG);
}

private string adjustKeyPath(in string keyPath, in bool useSystemDirs) {
    import std.string;

    version(Posix) {
        if(keyPath.startsWith("/")) {
            return keyPath;
        } else {
            return getConfigDirLocation(useSystemDirs) ~ "/" ~ keyPath;
        }
    } else version(Windows) {
        if(keyPath[1..($ - 1)].startsWith(":\\")) {
            // Checking if starts with C:\\ or A:\\, etc.
            return keyPath;
        } else {
            return getConfigDirLocation(useSystemDirs) ~ "/" ~ keyPath;
        }
    } else {
        assert(0, "Need to implement key path adjustment for this Operating System!");
    }
}

class Configuration {
    NetworkConfiguration network;
    SecurityConfiguration security;
    DeploymentConfiguration deployment;

    this(NetworkConfiguration network, SecurityConfiguration security, DeploymentConfiguration deployment) {
        this.network = network;
        this.security = security;
        this.deployment = deployment;
    }

    static Configuration load(in string location, in bool useSystemDirs = false) {
        import std.file : exists, readText;

        enforce(exists(location), "File does not exist!");

        auto contents = readText(location);

        JSONValue v = parseJSON(contents);
        
        NetworkConfiguration nc = NetworkConfiguration(
            v["network"]["ip"].str,
            to!ushort(v["network"]["port"].integer),
            jsonValueToBool(v["network"]["useHTTPS"]),
        );

        SecurityConfiguration sc = SecurityConfiguration(
            adjustKeyPath(v["security"]["serverPublicKey"].str, useSystemDirs),
            adjustKeyPath(v["security"]["clientPublicKey"].str, useSystemDirs),
            adjustKeyPath(v["security"]["clientPrivateKey"].str, useSystemDirs)
        );

        DeploymentConfiguration dc = DeploymentConfiguration(jsonValueToBool(v["deployment"]["enable"]));

        return new Configuration(nc, sc, dc);
    }
}

struct NetworkConfiguration {
    immutable string serverAddress;
    immutable ushort serverPort;

    immutable bool useSecure;
}

struct SecurityConfiguration {
    immutable string serverPublicKey;

    immutable string clientPublicKey;
    immutable string clientPrivateKey;
}

struct DeploymentConfiguration {
    immutable bool enabled;
}