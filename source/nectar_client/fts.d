module nectar_client.fts;

import std.digest.sha;
import std.json;
import std.file;
import std.algorithm;
import std.net.curl;
import std.uni : toUpper;
import std.string : strip;

import nectar_client.client;
import nectar_client.util;

string getFTSCacheLocation(in bool useSystemDirs = false) @trusted {
    if(useSystemDirs) {
        version(Windows) {
            return "C:\\NectarClient\\fts-cache";
        } else version(Posix) {
            return "/var/nectar-client-fts";
        }
    } else {
        return getcwd() ~ PATH_SEPARATOR ~ "fts-cache";
    }
}

/// Class which handles all aspects of the File Transfer System (FTS)
class FTSManager {

    package {
        Client client;

        string rootCacheDir;
        string publicCacheDir;
        string userCacheDir;

        JSONValue _localChecksumIndex;

        FTSStore publicStore;
        FTSStore userStore;
    }

    this(Client client, in bool useSystemDirs) {
        this.client = client;

        this.rootCacheDir = getFTSCacheLocation(useSystemDirs);
        this.publicCacheDir = this.rootCacheDir ~ PATH_SEPARATOR ~ "public";
        this.userCacheDir = this.rootCacheDir ~ PATH_SEPARATOR ~ "usr";

        if(!exists(this.rootCacheDir)) {
            mkdir(this.rootCacheDir);
        }

        if(!exists(this.publicCacheDir)) {
            mkdir(this.publicCacheDir);
        }

        if(!exists(this.userCacheDir)) {
            mkdir(this.userCacheDir);
        }

        this.client.logger.info("Using FTS cache from: " ~ this.rootCacheDir);
    }

    /// Goes through the entire FTS cache on the local machine and generates the local checksum index
    /// for each file.
    void initalVerifyChecksums() @trusted {
        this.client.logger.info(" ------Generating local FTS checksum index (this could take a while!)...");

        this._localChecksumIndex = JSONValue();
        buildChecksumsDir(this.rootCacheDir, this._localChecksumIndex);

        this.client.logger.info(" ------Done!");

        this.publicStore = new FTSStore(FTSStoreType.PUBLIC, this);

        this.client.logger.info("Downloading inital checksum index from the server...");

        this.publicStore.downloadChecksumIndexFromServer();

        this.client.logger.info("Done!");

        this.publicStore.initalSearchForChanges();
    }

    private void buildChecksumsDir(in string directory, ref JSONValue rootJSON) @system {
        foreach(DirEntry e; dirEntries(directory, SpanMode.shallow)) {
            if(e.isDir()) {
                debug {
                    import std.stdio;
                    writeln("Entering directory ", e.name());
                }
                buildChecksumsDir(e.name(), rootJSON);
            } else {
                debug {
                    import std.stdio;
                    writeln("Build ", e.name());
                }
                rootJSON[e.name()] = generateFileSHA256Checksum(e.name());
                debug {
                    import std.stdio;
                    writeln("Built ", e.name());
                }
            }
        }
    }

    /// Downloads the server's checksum index again in case of new changes.
    /// Then we compare the local index to the server's index for server side changes.
    void verifyChecksumsPeriodic() @trusted {
        publicStore.downloadChecksumIndexFromServer();
        if(this.userStore !is null) {
            this.userStore.downloadChecksumIndexFromServer();
        }
    }
}

/++
    Represents the different possible types of FTS stores.
    Currently only the USER and a PUBLIC stores exist.
+/
enum FTSStoreType {
    USER = 0,
    PUBLIC = 1
}

/++
    Represents a File Transfer System (FTS) Store, for a user
    or the public store. This class handles updating the local cache based on
    the server's checksum index and also communicating with the server about
    changes.
+/
class FTSStore {
    immutable FTSStoreType storeType;

    @property FTSManager manager() @trusted { return cast(FTSManager) _manager; }
    @property private JSONValue checksumIndex() @trusted { return cast(JSONValue) _checksumIndex; }

    private shared FTSManager _manager;
    private shared JSONValue _checksumIndex;

    this(in FTSStoreType storeType, FTSManager manager) {
        this.storeType = storeType;
        this._manager = cast(shared) manager;
    }

    private void downloadChecksumIndexFromServer() {
        debug this.manager.client.logger.info("Downloading index...");

        string url = this.manager.client.apiURL ~ "/fts/checksumIndex?token=" ~ this.manager.client.sessionToken;

        auto logger = this.manager.client.logger; // Need this due to mixin

        issueGETRequest(url ~ "&public=" ~ (this.storeType == FTSStoreType.PUBLIC ? "true" : "false"), (ushort status, string content, CurlException ce) {
            mixin(RequestErrorHandleMixin!("Download checksum index", [200], true, false));

            JSONValue json;
            try {
                json = parseJSON(content);
            } catch(JSONException e) {
                logger.fatal("Checksum index returned invalid JSON, aborting!");
                // fatal throws object.Error
                return;
            }

            this._checksumIndex = json;
        });
    }

    package void initalSearchForChanges() @safe {
        final switch(this.storeType) {
            case FTSStoreType.PUBLIC:
                initalSearchForChangesPublicStore();
                break;
            case FTSStoreType.USER:
                initalSearchForChangesUserStore();
                break;
        }
    }

    private void initalSearchForChangesPublicStore() @trusted {
        // Search for differences in checksums between the server and client for the public store

        foreach(entry; this.checksumIndex.array()) {
            debug {
                import std.stdio;
                writeln(entry);
            }

            // Check if we have the file downloaded in the cache
            if(!exists(this.manager.publicCacheDir ~ PATH_SEPARATOR ~ entry["path"].str())) {
                // We don't have the file saved, need to download it.
                downloadAndSaveFile(entry["path"].str());
            } else if(entry["checksum"].str().toUpper() != this.manager._localChecksumIndex[this.manager.publicCacheDir ~ PATH_SEPARATOR ~ entry["path"].str()].str().toUpper()) {
                // Check for difference between server's checksum for the file and our checksum for the file
                debug this.manager.client.logger.warning("Checksum difference for " ~ entry["path"].str());

                // There is a difference in the checksums. Since this is a public store, the user shouldn't be able to modify files.
                // So we assume this is a server-side change and redownload the file.
                // TODO: BETTER SOLUTION, ADMINS CAN CHANGE WHEN LOGGED IN AND HERE SHOULD PROPERLY CHECK FOR last-modified-by
                // TODO: DELTA COMPRESSION

                std.file.remove(this.manager.publicCacheDir ~ PATH_SEPARATOR ~ entry["path"].str()); // Delete the file we have saved
                downloadAndSaveFile(entry["path"].str()); // Redownload the file
            }
        }

        // TODO: Implement checking if a file was deleted on the server side.
        
        /*
        foreach(string key, JSONValue entry; this.manager._localChecksumIndex.object) {
            debug {
                import std.stdio;
                writeln(key, " ", entry);
            }
        }*/
    }

    private void initalSearchForChangesUserStore() @trusted {

    }

    private void downloadAndSaveFile(in string path) {
        string url = this.manager.client.apiURL ~ "/fts/download?token=" ~ this.manager.client.sessionToken ~ "&public=" ~ (this.storeType == FTSStoreType.PUBLIC ? "true" : "false") ~ "&path=" ~ urlsafeB64Encode(path);

        issueGETRequestDownload(url, 
            (this.storeType == FTSStoreType.PUBLIC ? this.manager.publicCacheDir : (this.manager.userCacheDir ~ PATH_SEPARATOR ~ this.manager.client.loggedInUser))
            ~ PATH_SEPARATOR ~ path
        );

        debug {
            import std.stdio;
            writeln("saving to, ", (this.storeType == FTSStoreType.PUBLIC ? this.manager.publicCacheDir : (this.manager.userCacheDir ~ PATH_SEPARATOR ~ this.manager.client.loggedInUser))
            ~ PATH_SEPARATOR ~ path);
        }
    }
}