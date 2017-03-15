module nectar_client.client;

import std.json;
import std.file;
import std.conv;
import std.string;
import std.algorithm;
import std.concurrency : Tid, spawn, receiveTimeout;
import std.experimental.logger;

import core.thread;
import core.stdc.stdlib : exit;

import nectar_client.logging;
import nectar_client.jwt;
import nectar_client.util;
import nectar_client.config;
import nectar_client.scheduler;
import nectar_client.service;
import nectar_client.operation;

immutable string SOFTWARE = "Nectar-Client";
immutable string SOFTWARE_VERSION = "1.0.0-alpha1";
immutable string RUNTIME = "DRUNTIME, compiled by " ~ __VENDOR__ ~ ", version " ~ to!string(__VERSION__);
immutable string API_MAJOR = "3";
immutable string API_MINOR = "1";

class Client {
    /++
        True if the client is accessing configuration files and keys
        from system directories, false if from current directory.
    ++/
    immutable bool useSystemDirs;

    immutable bool isService;

    package {
        shared bool running = false;
    }

    private {
        shared Tid consoleListenTid;

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

        shared OperationStatus currentOperationStatus;
        shared ptrdiff_t currentOperation = -1;
        shared size_t nextOperation = 0;
        shared Operation[size_t] _operationQueue;
        shared Tid _operationProcessingTid;
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

    @property Operation[size_t] operationQueue() @trusted nothrow { return cast(Operation[size_t]) this._operationQueue; }
    @property Tid operationProcessingTid() @trusted nothrow { return cast(Tid) this._operationProcessingTid; }

    public this(in bool useSystemDirs, in bool isService) @trusted {
        this.useSystemDirs = useSystemDirs;
        this.isService = isService;

        this._logger = cast(shared) new NectarLogger(LogLevel.trace, getLogLocation(useSystemDirs), isService ? false : true);
        this._scheduler = cast(shared) new Scheduler(this);

        this.logger.info("SERVICE MODE: " ~ to!string(isService));

        if(isService) {
            // nectar_client.service
            this.consoleListenTid = cast(shared) spawn(&consoleListenThread);
            this.scheduler.registerTask(Task.constructRepeatingTask(() {
                receiveTimeout(5.msecs, (string message) {
                    processMessageFromServiceProcess(message);
                });
            }, 100));
        }

        this.scheduler.registerTask(Task.constructRepeatingTask(&this.processOperationsQueue, 100));
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

        // Shutting down...
        shutdown();

        logger.info("Shutdown complete.");
     }

     private void shutdown() @trusted {
        this.switchState(ClientState.SHUTDOWN, false, true);

        // TODO: Determine if restarting or shutdown.

        //std.file.remove
        remove(getConfigDirLocation() ~ PATH_SEPARATOR ~ "savedToken.txt"); // TODO: Delete saved token only if not restarting.
     }

     private void processMessageFromServiceProcess(in string message) @safe {
        // TODO: Process more service messages.
        if(message == "SERVICESTOP") {
            this.stop();
        }
     }

     /++
        Checks the operations queue for new operations to process, and if there is
        one currently processing, checks for messages from it's worker thread.
     +/
     private void processOperationsQueue() @trusted {
        if(this.operationQueue.length < 1) return;

        if(this.currentOperation == -1) {
            // Queue is not empty, but we are not processing anything. Need to process nextOperation.
            Operation toProcess = this.operationQueue[this.nextOperation++];
            this._operationProcessingTid = cast(shared) spawn(&operationProcessingThread, cast(shared) this, cast(shared) toProcess);
            debug this.logger.info("Began processing operation " ~ to!string(toProcess.operationNumber));

            this.updateOperationStatus(OperationStatus.IN_PROGRESS, "Operation Worker Thread started.");
            return;
        }

        // Queue is not empty, we are processing things. Check for messages from thread.
        receiveTimeout(1.msecs, (string message) {
            string[] exploded = split(message, "~");

            // Thread is done!
            if(exploded[0] == "WORKER-SUCCESS") {
                this.updateOperationStatus(OperationStatus.SUCCESS, exploded[1]);
                this.currentOperation = -1;
                this.processOperationsQueue(); // check if there is another one to do.
                return;
            } else if(exploded[0] == "WORKER-FAILED") {
                // TODO: Operation Message send to server
                this.updateOperationStatus(OperationStatus.FAILED, exploded[1]);
                this.currentOperation = -1;
                this.processOperationsQueue(); // check if there is another one to do.
                return;
            }
        });
     }

     private void doDeployment() @trusted {
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
            mixin(RequestErrorHandleMixin!("deployment join request", [200], false, false));

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
            mixin(RequestErrorHandleMixin!("inital connect", [200], false, false));

            if(failure) {
                if(this.initalConnectTries >= 5) {
                    this.logger.error("Failed to do initalConnect, maximum tries reached.");
					exit(1);
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
                    logger.error(url ~ " Returned INVALID JSON, maximum tries reached.");
					exit(1);
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
                } else if(json["serverID"].str != this._serverID) {
                    this.logger.warning("Loaded token from disk, but has a different serverID.");
                    this._requestToken(inital, savedTokenLocation);
                    return;
                } else {
                    this.logger.info("Loaded token from disk!");

                    this._sessionToken = savedTokenContents;

                    this.switchState(ClientState.ONLINE, true);

                    // Set up repeating task to "renew" token.
                    this.scheduler.registerTask(Task.constructRepeatingTask(() { requestToken(); }, expires + 1000, false), true);
                    // Set up task to periodically ping the server and sync our status.
                    this.scheduler.registerTask(Task.constructRepeatingTask(&this.sendPing, 15000), true);
                    // Set up repeating task to check for new operations.
                    this.scheduler.registerTask(Task.constructRepeatingTask(&this.checkOperationQueue, 5000), true);

                    return; // Done!
                }
            }
        } else {
            this._requestToken(inital, savedTokenLocation);
            this.switchState(ClientState.ONLINE, true);
        }
     }

    private void _requestToken(in bool inital, in string savedTokenLocation) @system {
        import std.net.curl : CurlException;

        string url = this.apiURL ~ "/session/tokenRequest?uuid=" ~ this.uuid ~ "&auth=" ~ this.authStr;

        this.logger.info("Requesting new session token...");

        issueGETRequest(url, (ushort status, string content, CurlException ce) {
            mixin(RequestErrorHandleMixin!("token request", [200], false, false));

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

            if(inital) {
                // Set up repeating task to "renew" token.
                this.scheduler.registerTask(Task.constructRepeatingTask(() { requestToken(); }, json["expires"].integer + 1000, false), true);
                // Set up task to periodically ping the server and sync our status.
                this.scheduler.registerTask(Task.constructRepeatingTask(&this.sendPing, 15000), true);
                // Set up repeating task to check for new operations.
                this.scheduler.registerTask(Task.constructRepeatingTask(&this.checkOperationQueue, 5000), true);
            }

            this._sessionToken = content.strip();

            //std.file.write
            write(savedTokenLocation, content); // Save token to disk
            this.logger.info("Got new token from server (saved to disk).");
        });
    }

    private void switchState(in ClientState state, in bool inital = false, in bool isShutdown = false) @trusted {
        import std.net.curl : CurlException;

        string url = this.apiURL ~ "/session/updateState?token=" ~ this.sessionToken ~ "&state=" ~ to!string(to!int(state));
        issueGETRequest(url, (ushort status, string content, CurlException ce) {
            mixin(RequestErrorHandleMixin!("switch state", [204, 304], false, false));
            // Accepting 204 (NO CONTENT) and 304 (NOT MODIFIED)
            // 304 is also success, as that means the state is already the state we are switching to.

            if(failure) {
                if(isShutdown) {
                    this.logger.error("Failed to switch state!");
                    return;
                } else {
                    if(inital && status == 403) {
                        this.logger.warning("Perhaps the token is bad? Requesting new...");
                        this.requestToken(false);
                        return;
                    } else {
                        this.logger.warning("Retrying switch state in 2 seconds...");
                        this.scheduler.registerTask(Task.constructDelayedStartTask(() {
                            switchState(state);
                        }, 2000));
                        return;
                    }
                }
            } else {
                this.logger.info("Switched state to " ~ to!string(state));
            }
        });
    }

    private void sendPing() @trusted {
        import std.net.curl : CurlException;

        string url = this.apiURL ~ "/session/clientPing?token=" ~ this.sessionToken ~ "&data=" ~ urlsafeB64Encode(getUpdatesInfo().toString());
        issueGETRequest(url, (ushort status, string content, CurlException ce) {
            mixin(RequestErrorHandleMixin!("send client ping", [204], false, false));

            if(failure) {
                this.logger.warning("Retrying send ping in 2 seconds...");
                this.scheduler.registerTask(Task.constructDelayedStartTask(&this.sendPing, 2000));
                return;
            }

            debug this.logger.info("Send ping request.");
        });
    }

    private void checkOperationQueue() @trusted {
        import std.net.curl : CurlException;

        string url = this.apiURL ~ "/operation/getQueue?token=" ~ this.sessionToken;
        issueGETRequest(url, (ushort status, string content, CurlException ce) {
            mixin(RequestErrorHandleMixin!("check operation queue", [200], false, true)); // Return if there is an error, task runs every 5 seconds so no need to reschedule

            if(!verifyJWT(content, this.serverPublicKey)) {
                this.logger.warning("Failed to verify JWT from server while checking operation queue.");
                // Task runs every 5 seconds, no need to reschedule.
                return;
            }

            JSONValue json;
            try{
                json = parseJSON(getJWTPayload(content));
            } catch(Exception e) {
                this.logger.warning("Failed to get and parse JSON from server while checking operation queue.");
                return;
            }

            JSONValue[] array = json["array"].array;
            foreach(operation; array) {
                if(!(operation["operationNumber"].integer in this.operationQueue)) {
                    Operation o = Operation(operation["operationNumber"].integer, opIDFromInt(operation["id"].integer), operation["payload"]);
                    this.operationQueue[o.operationNumber] = o;
                    debug this.logger.info("Added operation " ~ to!string(o.id) ~ " to the queue.");
                }
            }
        });
    }

    private void updateOperationStatus(in OperationStatus opStatus, in string message, in int operationNumber = -1) @trusted {
        import std.net.curl : CurlException;

        JSONValue root = JSONValue();
        root["operationNumber"] = operationNumber;
        root["state"] = opStatus;
        root["message"] = message;

        string url = this.apiURL ~ "/operation/updateStatus?token=" ~ this.sessionToken ~ "&status=" ~ urlsafeB64Encode(root.toString());
        issueGETRequest(url, (ushort status, string content, CurlException ce) {
            mixin(RequestErrorHandleMixin!("update operation status", [204], false, false));
            
            if(failure) {
                this.logger.warning("Retrying updateOperationStatus in 1 second...");
                this.scheduler.registerTask(Task.constructDelayedStartTask(() { 
                    updateOperationStatus(opStatus, message, operationNumber); 
                }, 1000));
                return;
            }

            debug this.logger.info("Updated operation status on server.");
        });
    }
}