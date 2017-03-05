module nectar_client.client;

import std.json;
import std.file;
import std.conv;
import std.algorithm;
import std.experimental.logger;

import core.stdc.stdlib : exit;

import nectar_client.logging;
import nectar_client.util;
import nectar_client.config;
import nectar_client.scheduler;

immutable string SOFTWARE = "Nectar-Client";
immutable string SOFTWARE_VERSION = "1.0.0-alpha1";
immutable string RUNTIME = "DRUNTIME, compiled by " ~ __VENDOR__ ~ ", version " ~ to!string(__VERSION__);
immutable string API_MAJOR = "2";
immutable string API_MINOR = "3";

class Client {
    /++
        True if the client is accessing configuration files and keys
        from system directories, false if from current directory.
    ++/
    immutable bool useSystemDirs;

    package {
        shared bool running = false;
    }

    private {
        shared string _apiURL;
        shared string _apiURLRoot;

        shared Logger _logger;
        shared Scheduler _scheduler;

        shared Configuration _config;

        shared string _serverID;
    }

    @property Logger logger() @trusted nothrow { return cast(Logger) this._logger; }
    @property Scheduler scheduler() @trusted nothrow { return cast(Scheduler) this._scheduler; }

    @property Configuration config() @trusted nothrow { return cast(Configuration) this._config; }

    @property string apiURL() @trusted nothrow { return cast(string) this._apiURL; }
    @property string apiURLRoot() @trusted nothrow { return cast(string) this._apiURLRoot; }

    public this(bool useSystemDirs) @trusted {
        this.useSystemDirs = useSystemDirs;
        this._logger = cast(shared) new NectarLogger(LogLevel.trace, getLogLocation(useSystemDirs));
        this._scheduler = cast(shared) new Scheduler(this);
    }

    private void loadLibraries() @system {
        import derelict.jwt.jwt : DerelictJWT;
        import derelict.util.exception;
        try {
            DerelictJWT.load();
            logger.info("Loaded DerelictJWT!");
        } catch(DerelictException e) {
            logger.trace(e.toString());
            logger.fatal("FAILED TO LOAD DerelictJWT!");
            exit(1);
        }
    }

    private void loadConfig() @system {
        string cfgLocation = getConfigDirLocation(useSystemDirs) ~ PATH_SEPARATOR ~ "client.json";

        if(!exists(cfgLocation)) {
            this.logger.warning("Failed to find config: " ~ cfgLocation ~ ", creating new...");
            copyDefaultConfig(cfgLocation);
        }

        this._config = cast(shared) Configuration.load(cfgLocation);

        this.logger.info("Loaded configuration.");
        
        this._apiURLRoot = (this.config.network.useSecure ? "https://" : "http://") ~ this.config.network.serverAddress
                        ~ ":" ~ to!string(this.config.network.serverPort) ~ "/nectar/api";
        this._apiURL = this.apiURLRoot ~ "/v/" ~ API_MAJOR ~ "/" ~ API_MINOR;

        this.loadUUIDAndAuth();
    }

    private void loadUUIDAndAuth() @system {
        string uuidLocation = getConfigDirLocation(useSystemDirs) ~ PATH_SEPARATOR ~ "uuid.txt";
        string authLocation = getConfigDirLocation(useSystemDirs) ~ PATH_SEPARATOR ~ "auth.txt";

        if(!exists(uuidLocation) && !this.config.deployment.enabled) {
            this.logger.fatal("UUID File (" ~ uuidLocation ~ ") not found, deployment is not enabled, ABORTING!!!");
            // Fatal throws object.Error
            return;
        } else if(!exists(uuidLocation) && this.config.deployment.enabled) {
            this.logger.warning("UUID File (" ~ uuidLocation ~ ") not found, deployment is enabled, attempting deployment...");
            doDeployment();
        }

        if(!exists(authLocation) && !this.config.deployment.enabled) {
            this.logger.fatal("Auth File (" ~ authLocation ~ ") not found, deployment is not enabled, ABORTING!!!");
            // Fatal throws object.Error
            return;
        } else if(!exists(authLocation) && this.config.deployment.enabled) {
            this.logger.error("Auth File (" ~ authLocation ~ ") not found, deployment is enabled.");
            this.logger.fatal("Can't do deployment, UUID file exists but not auth. Delete the UUID file or create the auth file.");
            // Fatal throws object.Error
            return;
        }
    }

    public void stop() @safe {
        this.running = false;
    }

    public void run() @trusted {
        if(this.running) return;

        this.running = true;

        logger.info("Loading libraries...");
        loadLibraries();

        loadConfig();

        logger.info("Starting " ~ SOFTWARE ~ " version " ~ SOFTWARE_VERSION ~ ", implementing API " ~ API_MAJOR ~ "-" ~ API_MINOR);
        logger.info("Runtime: " ~ RUNTIME);

        initalConnect();

        scheduler.doRun();

        logger.info("Shutdown complete.");
     }

     private void doDeployment() {

     }

     private void initalConnect() @trusted {
         import std.net.curl : CurlException;

         string url = this.apiURLRoot ~ "/infoRequest";
         issueGETRequest(url, (ushort status, string content, CurlException ce) {
            mixin(RequestErrorHandleMixin!("inital connect", 200, false, false));

            if(failure) {
                logger.warning("Failed to do initalConnect, retrying in 5 seconds...");
                this.scheduler.registerTask(Task.constructDelayedStartTask(&this.initalConnect, 5000));
                return;
            }

            debug {
                import std.conv : to;
                logger.info("infoRequest, Got response: (" ~ to!string(status) ~ "): " ~ content);
            }

            JSONValue json;
            try {
                json = parseJSON(content);
            } catch(JSONException e) {
                logger.warning(url ~ " Returned INVALID JSON, retrying in 5 seconds...");
                this.scheduler.registerTask(Task.constructDelayedStartTask(&this.initalConnect, 5000));
                return;
            }

            if(json["apiVersionMajor"].integer != to!int(API_MAJOR)) {
                this.logger.fatal("Server API_MAJOR version (" ~ to!string(json["apiVersionMajor"].integer) 
                    ~ ") is incompatible with ours! (" ~ API_MAJOR ~ ")");
                return;
            }

            if(json["apiVersionMinor"].integer != to!int(API_MINOR)) {
                this.logger.warning("Server API_MINOR version (" ~ to!string(json["apiVersionMinor"].integer) 
                    ~ ") is differs with ours (" ~ API_MAJOR ~ ")");
            }

            this._serverID = json["serverID"].str;

            this.logger.info("Inital Request to " ~ url ~ " succeeded.");
            this.requestToken(true);
         });
     }

     private void requestToken(bool inital = false) @safe {
        this.logger.info("Requesting new session token...");

        string url = this.apiURL ~ "/session/tokenRequest?";
     }
}