import * as request from "request";
import * as winston from "winston";
import * as jsonwebtoken from "jsonwebtoken";

import * as readline from "readline";
import * as fs from "fs";
import * as os from "os";

import * as util from "./util";
import * as network from "./network";

export const SOFTWARE = "Nectar-Client"
export const SOFTWARE_VERSION = "0.1.2-alpha1";
export const API_VERSION_MAJOR = "1";
export const API_VERSION_MINOR = "2";

export const STATE_NORMAL = 0;
export const STATE_SLEEP = 1;
export const STATE_SHUTDOWN = 2;
export const STATE_REBOOT = 3;

function setupConsole(client: Client) {
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });

    rl.on("SIGINT", () => {
        client.shutdown();
    });
}

var shutdownStateTries = 0;

export class Client {
    public logger: winston.LoggerInstance;
    public config: any;
    protected info: any;

    private _network: network.DaemonSocketHandler;

    private _uuid: string;

    private _token: string;

    private _serverPublicKey: any;

    private _clientPrivateKey: any;
    private _clientPublicKey: any;

    // SETUP Methods ------------------------------------------------------------------------------------------------------

    private loadConfig() {
        var configLocation: string;

        if(process.env.NECTAR_USE_SYSTEM) { // Check if the system enviorment variable is set.
            configLocation = util.getConfigFileLocation(true);
        } else {
            configLocation = util.getConfigFileLocation(false);
        }

        this.config = util.loadConfig(configLocation);

        this.logger.notice("Loaded configuration from " + configLocation);
    }

    private loadKeys() {
        let publicLocation: string = this.config.security.serverPublicKey;

        let privateLocation2: string = this.config.security.clientPrivateKey;
        let publicLocation2: string = this.config.security.clientPublicKey;

        if(publicLocation == null) {
            this.logger.error("Invalid config.");
            this.logger.error("Missing required fields security.serverPublicKey.");
            process.exit(1);
        }

        if(privateLocation2 == null || publicLocation2 == null) {
            this.logger.error("Invalid config.");
            this.logger.error("Missing required fields security.clientPublicKey OR security.clientPrivateKey.");
            process.exit(1);
        }

        if(!fs.existsSync(publicLocation) || !fs.existsSync(privateLocation2) || !fs.existsSync(publicLocation2)) {
            this.logger.error("FAILED TO FIND ES384 KEYS!");
            this.logger.error("Could not find key files as specified in config.");
            this.logger.error("Please generate the keys first using the provided script.");
            process.exit(1);
        }

        this._serverPublicKey = fs.readFileSync(publicLocation);

        this._clientPrivateKey = fs.readFileSync(privateLocation2);
        this._clientPublicKey = fs.readFileSync(publicLocation2);
    }

    private setupLogger() {
        this.logger = new winston.Logger({
            transports: [
                new winston.transports.Console({colorize: true})
            ],
            levels: {
                debug: 0,
                info: 1,
                notice: 2,
                warn: 3,
                error: 4
            },
            level: "error"
        });

        winston.addColors({
            debug: "white",
            info: "green",
            notice: "blue",
            warn: "yellow",
            error: "red"
        });
    }

    private setupInfoObject() {
        this.info = {
            software: SOFTWARE,
            version: SOFTWARE_VERSION,
            apiMajor: API_VERSION_MAJOR,
            apiMinor: API_VERSION_MINOR
        };

        if(this.config.network.sendSystemData) {
            this.info.system = {
                hostname: os.hostname,
                os: os.platform(),
                osver: os.release(),
                arch: os.arch(),
                cpuCount: os.cpus().length,
                cpu: os.cpus()[0].model
            };
        }
    }

    private initUUID() {
        this._uuid = util.loadUUID(util.getConfigDirLocation(process.env.NECTAR_USE_SYSTEM) + "/uuid.txt");
        this.logger.notice("UUID is " + this._uuid);
    }

    constructor() {
        setupConsole(this);

        this.setupLogger();
        this.loadConfig();
        this.loadKeys();
        this.setupInfoObject();
        this.initUUID();

        this._network = new network.DaemonSocketHandler(this);
    }

    public run() {
        this.requestToken(true, () => {
            this.switchState(STATE_NORMAL, this.onSwitchStateCB.bind(this)); // Switch to normal state
            setInterval(this.doServerPing.bind(this), 15000); // Send pings every 15 seconds
        });
    }

    public shutdown(state: Number = STATE_SHUTDOWN) {
        this.logger.notice("Got shutdown signal.");

        this._network.shutdown();

        // TODO: Do shutdown stuff

        function shutdownCB(state: Number, success: boolean) {
            if(shutdownStateTries >= 5) { // 5 tries before force shutdown
                this.logger.error("Failed to switch state in 5 tries, force shutdown.");
                process.exit(1);
            }
            if(!success) {
                setTimeout(() => {
                    this.switchState(state, shutdownCB.bind(this));
                }, 1000); // Try again in one second
                shutdownStateTries++;
            } else {
                process.exit(0);
            }
        }

        this.switchState(state, shutdownCB.bind(this));
    }

    // Client Operations ------------------------------------------------------------------

    private requestToken(inital: boolean = false, cb: ()=>void = () => {}) {
        if(inital) {
            // The inital token request, attempt to load from disk if it was saved.
            let t = util.loadToken(util.getConfigDirLocation(process.env.NECTAR_USE_SYSTEM) + "/token.txt");
            if(t !== "none") {
                // The token was saved! Save it to memory and then attempt to calculate the expire time
                this._token = t;
                var decoded = jsonwebtoken.decode(this._token);

                if(decoded && decoded.timestamp && decoded.expires) {
                    // Token has been decoded, now check expiration
                    if(((new Date).getTime() - decoded.timestamp) >= decoded.expires) { // Check if the token has expired
                        this.logger.warn("Loaded token from disk, but it has expired. Requesting new...");
                        // We now move on to request the new token from the server.
                    } else {
                        // token has not expired, we are done
                        this.logger.notice("Loaded token from disk.");

                        // Set task to renew token after expire
                        setTimeout(() => {
                            this.requestToken();
                        }, decoded.expires + 1000);

                        cb();
                        return;
                    }
                } else {
                    // The decode failed or there are missing key-value pairs.
                    this.logger.warn("Loaded token from disk, but it is not valid. Requesting new...");
                }
            }
        }

        this.logger.debug("Requesting new token from server...");
        request(this.nectarAddressFull + "auth/tokenRequest?uuid=" + this.uuid + "&info=" + this.info, (error, response, body) => {
            if(error) {
                this.logger.error("FAILED TO REQUEST TOKEN!");
                console.log(error);
                process.exit(1);
            }

            if(response.statusCode !== 200) { // 200: OK
                this.logger.error("Received non 200 status code from server while requesting token:");
                this.logger.error(response.statusCode + ": " + body);
                process.exit(1);
            }

            this.logger.info("Received new token from server.");
            jsonwebtoken.verify(body, this.serverPublicKey, (err: any, decoded: any) => {
                if(err) {
                    this.logger.error("FAILED TO VERIFY TOKEN!");
                    console.log(error);
                    process.exit(1);
                } else {
                    // Set up the token renew task
                    setTimeout(() => {
                        this.requestToken();
                    }, decoded.expires + 1000);
                }
            });
            this._token = body;
            cb();
        });
    }

    private doServerPing() {
        this.logger.debug("Sending ping update...");

        let data = {
            securityUpdates: 0,
            otherUpdates: 0
        }; // TODO: determine these

        request(this.nectarAddressFull + "client/ping?token=" + this.token + "&data=" + data, (error, response, body) => {
            if(error) {
                console.log(error);
                this.logger.warn("Error while processing ping update to server ^^^.");
                return;
            }

            if(response.statusCode !== 204) {
                this.logger.warn("Received a non 204 status code while sending ping update to server:");
                this.logger.warn(response.statusCode + ": " + body);
                return;
            }
        });
    }

    private switchState(state: Number = 0, cb: (state: Number, success: boolean)=>void) {
        this.logger.debug("Switching state to " + state);

        if(state == STATE_REBOOT) { // Rebooting state does not issue new tokens, save ours to disk.
            util.saveToken(util.getConfigDirLocation(process.env.NECTAR_USE_SYSTEM) + "/token.txt", this.token);
        }

        request(this.nectarAddressFull + "client/switchState?token=" + this.token + "&state=" + state, (error, response, body) => {
            if(error) {
                this.logger.warn("Failed to switch state!");
                console.log(error);
                process.exit(1);
            }

            if(response.statusCode !== 204) { // 200: No Content
                this.logger.warn("Received a non 204 status code while switching state:");
                this.logger.warn(response.statusCode + ": " + body);
                cb(state, false);
                return;
            }

            this.logger.info("Switched state to " + state);
            cb(state, true);
        });
    }

    /// Callback functions -------------------------------------------------------------------------------------------

    private onSwitchStateCB(state: Number, success: boolean) {
        if(!success) {
            setTimeout(() => {
                this.switchState(state, this.onSwitchStateCB.bind(this));
            }, 1000); // Try again in one second
        }
    }

    // Getters and Setters -----------------------------------------------------------------

    get uuid(): string {
        return this._uuid;
    }

    get token(): string {
        return this._token;
    }

    get serverPublicKey(): any {
        return this._serverPublicKey;
    }

    get clientPublicKey(): any {
        return this._clientPublicKey;
    }

    get clientPrivateKey(): any {
        return this._clientPrivateKey;
    }

    get nectarAddressFull(): string {
        var protocol = this.config.network.useHTTPS ? "https://" : "http://";
        return protocol + this.config.network.ip + ":" + this.config.network.port + "/nectar/api/" + API_VERSION_MAJOR + "/" + API_VERSION_MINOR + "/";
    }
}
