import * as request from "request";
import * as winston from "winston";

import * as readline from "readline";
import * as fs from "fs";
import * as os from "os";

import * as util from "./util";

export const SOFTWARE = "Nectar-Client"
export const SOFTWARE_VERSION = "0.1.2-alpha1";
export const API_VERSION_MAJOR = "1";
export const API_VERSION_MINOR = "2";

function setupConsole(client: Client) {
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });

    rl.on("SIGINT", () => {
        client.shutdown();
    });
}

export class Client {
    public logger: winston.LoggerInstance;
    public config: any;
    protected info: any;

    private _uuid: string;

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
        var publicLocation: string = this.config.security.serverPublicKey;

        var privateLocation2: string = this.config.security.clientPrivateKey;
        var publicLocation2: string = this.config.security.clientPublicKey;

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
        
    }

    constructor() {
        setupConsole(this);

        this.setupLogger();
        this.loadConfig();
        this.loadKeys();
        this.setupInfoObject();
        this.initUUID();
    }

    public run() {
        this.requestToken();
    }

    public shutdown() {

    }

    // Client Operations ------------------------------------------------------------------

    private requestToken() {

    }

    // Getters and Setters -----------------------------------------------------------------

    get uuid(): string {
        return this._uuid;
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
