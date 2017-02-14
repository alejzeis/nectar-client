import * as fs from "fs";
import * as os from "os";
import * as ini from "ini";
import * as uuid from "uuid";
import * as child_process from "child_process";

const DEFAULT_CONFIG =
`; Nectar-Client Config File\n
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
`;

export function getConfigDirLocation(system: boolean = false): string {
    if(!system) {
        return process.cwd(); // Current directory
    }

    switch(os.platform()) {
        case "darwin":
        case "freebsd":
        case "linux":
        case "openbsd":
            return "/etc/nectar-client";
        default:
            // Store in the current directory by default.
            return process.cwd();
    }
}

export function getConfigFileLocation(system: boolean = false): string {
    return getConfigDirLocation(system) + "/client.ini";
}

export function loadConfig(location: string): any {
    if(!fs.existsSync(location)) {
        fs.writeFileSync(location, DEFAULT_CONFIG);
    }
    var config = ini.parse(fs.readFileSync(location, "utf-8"));
    return config;
}

export function loadUUID(location: string): string {
    if(!fs.existsSync(location)) {
        var id = uuid.v4();
        fs.writeFileSync(location, id);
        return id;
    }
    return fs.readFileSync(location, 'utf8').split("\n")[0];
}

export function loadAuthStr(location: string): string {
    if(!fs.existsSync(location)) {
        return null;
    }
    return fs.readFileSync(location, 'utf8').split("\n")[0];
}

export function loadToken(location: string): string {
    if(!fs.existsSync(location)) {
        return "none";
    }
    return fs.readFileSync(location, 'utf8').split("\n")[0];
}

export function saveToken(location: string, token: string) {
    fs.writeFileSync(location, token);
}

export function getUpdateInfo(): any {
    if(os.platform() === "linux") {
        // TODO: Support other package managers.
        let output = child_process.spawnSync("/usr/lib/update-notifier/apt-check").stdout;

        if(!output) {
            return {
                security: -1,
                other: -1
            };
        }

        if(output.toString().includes(";")) {
            let split = output.toString().split(";");
            return {
                security: parseInt(split[0]),
                other: parseInt(split[1])
            }
        }
    } else {
        return {
            security: -1,
            other: -1
        };
    }
}
