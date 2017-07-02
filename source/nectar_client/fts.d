module nectar_client.fts;

import std.digest.sha;
import std.json;
import std.file;

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
    }

    private void buildChecksumsDir(in string directory, ref JSONValue rootJSON) @system {
        foreach(DirEntry e; dirEntries(directory, SpanMode.shallow)) {
            if(e.isDir()) {
                buildChecksumsDir(e.name(), rootJSON);
            } else {
                rootJSON[e.name()] = generateFileSHA256Checksum(e.name());
            }
        }
    }

    /// Compares the local checksum index to the server's checksum index. If differences are found
    /// the new files/deltas are downloaded and replaced/applied.
    void verifyChecksumsPeriodic() @trusted {

    }
}