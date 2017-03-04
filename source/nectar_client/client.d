module nectar_client.client;

import std.json;
import std.file;
import std.conv;
import std.experimental.logger;

import core.stdc.stdlib : exit;

import nectar_client.logging;
import nectar_client.util;
import nectar_client.config;
import nectar_client.scheduler;

immutable string SOFTWARE = "Nectar-Client";
immutable string SOFTWARE_VERSION = "1.0.0-alpha1";
immutable string API_MAJOR = "2";
immutable string API_MINOR = "3";

class Client {
    /++
        True if the client is accessing configuration files and keys
        from system directories, false if from current directory.
    ++/
    immutable bool useSystemDirs;

    private shared string _apiURL;
    private shared string _apiURLRoot;

    package shared bool running = false;

    private shared Logger _logger;
    private shared Scheduler _scheduler;

    private shared Configuration _config;

    @property Logger logger() @trusted nothrow { return cast(Logger) this._logger; }
    @property Scheduler scheduler() @trusted nothrow { return cast(Scheduler) this._scheduler; }

    @property Configuration config() @trusted nothrow { return cast(Configuration) this._config; }

    @property string apiURL() @trusted nothrow { return cast(string) this._apiURL; }
    @property string apiURLRoot() @trusted nothrow { return cast(string) this._apiURLRoot; }

    public this(bool useSystemDirs) @trusted {
        this.useSystemDirs = useSystemDirs;
        this._logger = cast(shared) new NectarLogger(LogLevel.trace, "log.txt");
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

        initalConnect();

        scheduler.doRun();

        logger.info("Shutdown complete.");
     }

     private void initalConnect() {
         import std.net.curl : CurlException;

         string url = this.apiURL ~ "/infoRequest";
         issueGETRequest(url, (ushort status, string content, CurlException e) {
            if(!(e is null)) {
                logger.error("Failed to connect to " ~ url ~ ", CurlException.");
                logger.trace(e.toString());
                logger.fatal("Failed to process inital connect!");
                return;
            }

            if(status != 200) { // 200: OK
                logger.error("Failed to connect to " ~ url ~ ", server returned non-200 status code.");
                logger.fatal("Failed to process inital connect!");
                return;
            }

            debug {
                import std.conv : to;
                logger.info("Got response: (" ~ to!string(status) ~ "): " ~ content);
            }
         });
     }
}