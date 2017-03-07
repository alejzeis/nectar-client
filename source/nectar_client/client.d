module nectar_client.client;

import std.json;
import std.file;
import std.conv;
import std.string;
import std.algorithm;
import std.experimental.logger;

import core.thread;
import core.stdc.stdlib : exit;

import nectar_client.logging;
import nectar_client.jwt;
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
        size_t initalConnectTries = 0;

        shared string _apiURL;
        shared string _apiURLRoot;

        shared Logger _logger;
        shared Scheduler _scheduler;

        shared Configuration _config;

        shared string _serverID;

        shared string _serverPublicKey;
        shared string _clientPrivateKey;
        shared string _clientPublicKey;

        shared string _uuid;
        shared string _authStr;

        shared string _sessionToken;
    }

    @property Logger logger() @trusted nothrow { return cast(Logger) this._logger; }
    @property Scheduler scheduler() @trusted nothrow { return cast(Scheduler) this._scheduler; }

    @property Configuration config() @trusted nothrow { return cast(Configuration) this._config; }

    @property string apiURL() @trusted nothrow { return cast(string) this._apiURL; }
    @property string apiURLRoot() @trusted nothrow { return cast(string) this._apiURLRoot; }

    @property string serverPublicKey() @trusted nothrow { return cast(string) this._serverPublicKey; }
    @property string clientPrivateKey() @trusted nothrow { return cast(string) this._clientPrivateKey; }
    @property string clientPublicKey() @trusted nothrow { return cast(string) this._clientPublicKey; }

    @property string uuid() @trusted nothrow { return cast(string) this._uuid; }
    @property string authStr() @trusted nothrow { return cast(string) this._authStr; }

    @property string sessionToken() @trusted nothrow { return cast(string) this._sessionToken; }

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
    }

    private void loadKeys() @system {
        string serverPub = this.config.security.serverPublicKey;
        string clientPrivate = this.config.security.clientPrivateKey;
        string clientPublic = this.config.security.clientPublicKey;

        if(!exists(serverPub) || !exists(clientPrivate) || !exists(clientPublic)) {
            this.logger.fatal("Failed to find one or more of the following security keys: serverPublic, clientPrivate, clientPublic.");
            // Fatal throws object.Error
            return;
        }

        this._serverPublicKey = readText(serverPub);
        this._clientPrivateKey = readText(clientPrivate);
        this._clientPublicKey = readText(clientPublic);

        this.logger.info("Loaded keys.");
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

        this._uuid = readText(uuidLocation);
        this._authStr = readText(authLocation);

        this.logger.info("Our UUID is " ~ this.uuid);
    }

    public void stop() @safe {
        this.running = false;
    }

    public void run() @trusted {
        if(this.running) return;

        this.running = true;

        logger.info("Loading libraries...");
        loadLibraries();

        logger.info("Starting " ~ SOFTWARE ~ " version " ~ SOFTWARE_VERSION ~ ", implementing API " ~ API_MAJOR ~ "-" ~ API_MINOR);
        logger.info("Runtime: " ~ RUNTIME);

        this.loadConfig();

        this.initalConnect();

        this.loadKeys();
        this.loadUUIDAndAuth();

        this.requestToken(true);

        scheduler.doRun();

        logger.info("Shutdown complete.");
     }

     private void doDeployment() {
        import std.net.curl : CurlException;
        import std.string : strip;

        string uuidLocation = getConfigDirLocation(useSystemDirs) ~ PATH_SEPARATOR ~ "uuid.txt";
        string authLocation = getConfigDirLocation(useSystemDirs) ~ PATH_SEPARATOR ~ "auth.txt";

        string deployTokenFile = getConfigDirLocation(this.useSystemDirs) ~ PATH_SEPARATOR ~ "deploy.txt";

        if(!exists(deployTokenFile)) {
            this.logger.fatal("Deployment token (" ~ deployTokenFile ~ ") not found, aborting!");
            // Fatal throws object.Error
            return;
        }

        string deployTokenRaw = readText(deployTokenFile).strip();
        if(!verifyJWT(deployTokenRaw, this.serverPublicKey)) {
            this.logger.fatal("Deployment token (" ~ deployTokenFile ~ ") is not valid! (Failed to pass JWT verification, is it corrupt?)");
            // Fatal throws object.Error
            return;
        }

        string url = this.apiURL ~ "/deploy/deployJoin?token=" ~ deployTokenRaw;
        issueGETRequest(url, (ushort status, string content, CurlException ce) {
            mixin(RequestErrorHandleMixin!("deployment join request", 200, false, false));

            if(failure) {
                if(status == 503) {
                    this.logger.fatal("Deployment join request returned 503, deployment is NOT ENABLED ON THE SERVER!");
                    // fatal throws object.Error
                    return;
                } else {
                    this.logger.fatal("Deployment join request failed!");
                    // fatal throws object.Error
                    return;
                }
            }

            JSONValue json;
            try {
                json = parseJSON(content);
            } catch(JSONException e) {
                this.logger.fatal("Deployment join request returned invalid JSON, aborting!");
                // fatal throws object.Error
                return;
            }

            write(uuidLocation, json["uuid"].str);
            write(authLocation, json["auth"].str);

            this.logger.info("Deployment Succeeded! Our UUID is " ~ json["uuid"].str);
        });
     }

     private void initalConnect() @trusted {
         import std.net.curl : CurlException;

         string url = this.apiURLRoot ~ "/infoRequest";
         issueGETRequest(url, (ushort status, string content, CurlException ce) {
            mixin(RequestErrorHandleMixin!("inital connect", 200, false, false));

            if(failure) {
                if(this.initalConnectTries >= 5) {
                    this.logger.fatal("Failed to do initalConnect, maximum tries reached.");
                    return;
                }

                logger.warning("Failed to do initalConnect, retrying in 5 seconds...");
                //this.scheduler.registerTask(Task.constructDelayedStartTask(&this.initalConnect, 5000));

                Thread.sleep(5000.msecs);
                this.initalConnectTries++;
                this.initalConnect();
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
                if(this.initalConnectTries >= 5) {
                    logger.fatal(url ~ " Returned INVALID JSON, maximum tries reached.");
                    return;
                }

                logger.warning(url ~ " Returned INVALID JSON, retrying in 5 seconds...");
                //this.scheduler.registerTask(Task.constructDelayedStartTask(&this.initalConnect, 5000));

                Thread.sleep(5000.msecs);
                this.initalConnectTries++;
                this.initalConnect();
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
         });
     }

     private void requestToken(bool inital = false) @trusted {
        import std.net.curl : CurlException;

        string savedTokenLocation = getConfigDirLocation() ~ PATH_SEPARATOR ~ "savedToken.txt";

        if(inital && exists(savedTokenLocation)) {
            // Attempt to load token from disk
            string savedTokenContents = readText(savedTokenLocation).strip();
            if(!verifyJWT(savedTokenContents, this.serverPublicKey)) {
                this.logger.warning("Loaded token from disk, but failed to verify.");
                this._requestToken(inital, savedTokenLocation);
                return;
            } else {
                JSONValue json;
                try{
                    json = parseJSON(getJWTPayload(savedTokenContents));
                } catch(JSONException e) {
                    this.logger.warning("Loaded token from disk, but failed to parse JSON from payload.");
                    this._requestToken(inital, savedTokenLocation);
                    return;
                } catch(Exception e) {
                    this.logger.warning("Loaded token from disk, but failed to get payload and parse JSON.");
                    this._requestToken(inital, savedTokenLocation);
                    return;
                }

                ulong timestamp = json["timestamp"].integer;
                ulong expires = json["expires"].integer;

                if(getTimeMillis() - timestamp >= expires) {
                    this.logger.warning("Loaded token from disk, but it has expired.");
                    this._requestToken(inital, savedTokenLocation);
                    return;
                } else {
                    this.logger.info("Loaded token from disk!");

                    this._sessionToken = savedTokenContents;

                    // TODO: DO SWITCHSTATE

                    // Set up repeating task to "renew" token.
                    this.scheduler.registerTask(Task.constructRepeatingTask(() { requestToken(); }, expires + 1000, false));

                    return; // Done!
                }
            }
        } else {
            this._requestToken(inital, savedTokenLocation);
        }
     }

     private void _requestToken(in bool inital, in string savedTokenLocation) {
        import std.net.curl : CurlException;

        string url = this.apiURL ~ "/session/tokenRequest?uuid=" ~ this.uuid ~ "&auth=" ~ this.authStr;

        this.logger.info("Requesting new session token...");

        issueGETRequest(url, (ushort status, string content, CurlException ce) {
            mixin(RequestErrorHandleMixin!("token request", 200, false, false));

            if(failure) {
                this.logger.warning("Retrying token request...");

                // Repeating renew task will handle it, unless inital

                if(inital)
                    this.scheduler.registerTask(Task.constructDelayedStartTask(() {
                        requestToken(inital);
                    }, 1500));
                return;
            }

            debug this.logger.info("Got tokenRequest response from server (" ~ to!string(status) ~ ")");

            if(!verifyJWT(content.strip(), this.serverPublicKey)) {
                this.logger.error("Failed to verify Session Token from server, retrying...");

                 // Repeating renew task will handle it, unless inital

                if(inital)
                    this.scheduler.registerTask(Task.constructDelayedStartTask(() {
                        requestToken(inital);
                    }, 1500));
                return;
            }

            JSONValue json;
            try {
                json = parseJSON(getJWTPayload(content.strip()));
            } catch(JSONException e) {
                this.logger.error("Failed to parse Session Token JSON from server, retrying...");

                // Repeating task will handle it, unless inital

                if(inital)
                    this.scheduler.registerTask(Task.constructDelayedStartTask(() {
                        requestToken(inital);
                    }, 1500));
                return;
            }

            // Set up repeating task to "renew" token.

            if(inital)
                this.scheduler.registerTask(Task.constructRepeatingTask(() { requestToken(); }, json["expires"].integer + 1000, false));

            this._sessionToken = content.strip();

            //std.file.write
            write(savedTokenLocation, content); // Save token to disk
            this.logger.info("Got new token from server (saved to disk).");
        });
     }
}