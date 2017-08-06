module nectar_client.fts;

import std.digest.sha;
import std.json;
import std.file;
import std.algorithm;
import std.net.curl;

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

    private {
        Client client;

        string rootCacheDir;
        string publicCacheDir;
        string userCacheDir;

        JSONValue _checksumIndex;

        JSONValue _serverPublicChecksumIndex;
        JSONValue _serverUserChecksumIndex;
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

        this._checksumIndex = JSONValue();
        buildChecksumsDir(this.rootCacheDir, this._checksumIndex);

        this.client.logger.info(" ------Done!");

        this.client.logger.info("Downloading inital checksum index from the server...");

        downloadChecksumIndexFromServer();

        this.client.logger.info("Done!");

        initalSearchForChanges();
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

    private void downloadChecksumIndexFromServer() {
        // Download public index first
        debug this.client.logger.info("Downloading public index...");

        string url = this.client.apiURL ~ "/fts/checksumIndex?token=" ~ this.client.sessionToken;

        auto logger = this.client.logger; // Need this due to mixin

        issueGETRequest(url ~ "&public=true", (ushort status, string content, CurlException ce) {
            mixin(RequestErrorHandleMixin!("token request", [200], true, false));

            JSONValue json;
            try {
                json = parseJSON(content);
            } catch(JSONException e) {
                logger.fatal("Checksum index returned invalid JSON, aborting!");
                // fatal throws object.Error
                return;
            }

            this._serverPublicChecksumIndex = json;
        });

        if(this.client.loggedIn) {
            debug this.client.logger.info("Downloading user index...");

            issueGETRequest(url ~ "&public=false", (ushort status, string content, CurlException ce) {
                mixin(RequestErrorHandleMixin!("token request", [200], true, false));

                JSONValue json;
                try {
                    json = parseJSON(content);
                } catch(JSONException e) {
                    logger.fatal("Checksum index returned invalid JSON, aborting!");
                    // fatal throws object.Error
                    return;
                }

                this._serverUserChecksumIndex = json;
            });
        }
    }

    /// Downloads the server's checksum index again in case of new changes.
    /// Then we compare the local index to the server's index for server side changes.
    void verifyChecksumsPeriodic() @trusted {
        downloadChecksumIndexFromServer();
    }

    private void initalSearchForChanges() @trusted {
        // Search for differences in checksums between the server and client for the public store

        foreach(entry; this._serverPublicChecksumIndex.array()) {
            debug {
                import std.stdio;
                writeln(entry);
            }

            // Check if we have the file downloaded in the cache
            if(!exists(this.publicCacheDir ~ PATH_SEPARATOR ~ entry["path"].str())) {
                // We don't have the file saved, need to download it.
                downloadAndSaveFile(entry["path"].str(), true);
            } else if(entry["checksum"].str() != this._checksumIndex["public" ~ PATH_SEPARATOR ~ entry["path"].str()].str()) {
                // Check for difference between server's checksum for the file and our checksum for the file
            }
        }
    }

    private void downloadAndSaveFile(in string path, in bool isPublic) {
        string url = this.client.apiURL ~ "/fts/download?token=" ~ this.client.sessionToken ~ "&public=" ~ to!string(isPublic) ~ "&path=" ~ urlsafeB64Encode(path);

        // TODO: CURL DOWNLOAD
        issueGETRequestDownload(url, 
            (isPublic ? this.publicCacheDir : (this.userCacheDir ~ PATH_SEPARATOR ~ this.client.loggedInUser))
            ~ PATH_SEPARATOR ~ path
        );

        debug {
            import std.stdio;
            writeln("saving to, ", (isPublic ? this.publicCacheDir ~ PATH_SEPARATOR: (this.userCacheDir ~ PATH_SEPARATOR ~ this.client.loggedInUser))
            ~ PATH_SEPARATOR ~ path);
        }
    }
}