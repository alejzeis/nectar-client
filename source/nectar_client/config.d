module nectar_client.config;

import std.exception : enforce;
import std.json;
import std.conv;

import nectar_client.util;

immutable string DEFAULT_CONFIG = "
{
    \"network\" : {
        \"ip\": \"127.0.0.1\",
        \"port\": 8080,
        \"useHTTPS\": false,
        \"sendSystemData\": true
    },
    \"security\" : {
        \"serverPublicKey\": \"keys/server-pub.pem\",
        \"clientPublicKey\": \"keys/client-pub.pem\",
        \"clientPrivateKey\": \"keys/server.pem\"
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

void copyDefaultConfig(in string location) @trusted {
    import std.file : write;

    write(location, DEFAULT_CONFIG);
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

    static Configuration load(in string location) {
        import std.file : exists, readText;

        enforce(exists(location), "File does not exist!");

        auto contents = readText(location);

        JSONValue v = parseJSON(contents);
        
        NetworkConfiguration nc = NetworkConfiguration(
            v["network"]["ip"].str,
            to!ushort(v["network"]["port"].integer),
            jsonValueToBool(v["network"]["useHTTPS"]),
            jsonValueToBool(v["network"]["sendSystemData"])
        );

        SecurityConfiguration sc = SecurityConfiguration(
            v["security"]["serverPublicKey"].str,
            v["security"]["clientPublicKey"].str,
            v["security"]["clientPrivateKey"].str
        );

        DeploymentConfiguration dc = DeploymentConfiguration(jsonValueToBool(v["deployment"]["enable"]));

        return new Configuration(nc, sc, dc);
    }
}

struct NetworkConfiguration {
    immutable string serverAddress;
    immutable ushort serverPort;

    immutable bool useSecure;
    immutable bool sendSystemData;
}

struct SecurityConfiguration {
    immutable string serverPublicKey;

    immutable string clientPublicKey;
    immutable string clientPrivateKey;
}

struct DeploymentConfiguration {
    immutable bool enabled;
}