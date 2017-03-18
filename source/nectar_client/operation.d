module nectar_client.operation;

import std.conv;
import std.json;
import std.process;
import std.concurrency;

import nectar_client.client;

enum OperationStatus {
    IDLE = 0,
    IN_PROGRESS = 1,
    SUCCESS = 2,
    FAILED = 3
}

enum OperationID {
    OPERATION_DO_UPDATE = 0,
    OPERATION_INSTALL_PACAKGE = 1,
    OPERATION_UPDATE_CLIENT_EXECUTABLE = 2,
    OPERATION_SET_TIMEZONE = 20,
    OPERATION_DEPLOY_SCRIPT = 30,
    OPERATION_DO_SHUTDOWN = 40,
    OPERATION_DO_REBOOT = 41,
    OPERATION_BROADCAST_MESSAGE = 50
}

struct Operation {
    size_t operationNumber;
    OperationID id;
    JSONValue payload;
}

OperationID opIDFromInt(in size_t id) {
    switch(id) {
        case OperationID.OPERATION_DO_UPDATE:
            return OperationID.OPERATION_DO_UPDATE;
        case OperationID.OPERATION_INSTALL_PACAKGE:
            return OperationID.OPERATION_INSTALL_PACAKGE;
        case OperationID.OPERATION_UPDATE_CLIENT_EXECUTABLE:
            return OperationID.OPERATION_UPDATE_CLIENT_EXECUTABLE;
        case OperationID.OPERATION_SET_TIMEZONE:
            return OperationID.OPERATION_SET_TIMEZONE;
        case OperationID.OPERATION_DEPLOY_SCRIPT:
            return OperationID.OPERATION_DEPLOY_SCRIPT;
        case OperationID.OPERATION_DO_SHUTDOWN:
            return OperationID.OPERATION_DO_SHUTDOWN;
        case OperationID.OPERATION_DO_REBOOT:
            return OperationID.OPERATION_DO_REBOOT;
        case OperationID.OPERATION_BROADCAST_MESSAGE:
            return OperationID.OPERATION_BROADCAST_MESSAGE;
        default:
            throw new Exception("Unknown OperationID!");
    }
}

void operationProcessingThread(shared Client client, shared Operation operation) {
    try {
        switch(operation.id) {
            case OperationID.OPERATION_SET_TIMEZONE:
                setTimezoneImpl(cast(Client) client, operation.payload);
                break;
            case OperationID.OPERATION_UPDATE_CLIENT_EXECUTABLE:
                updateClientExecutableImpl(cast(Client) client, operation.payload);
                break;
            default:
                ownerTid.send("WORKER-FAILED~The operation given is unknown or not implemented.");
                return;
        }
    } catch(Exception e) {
        debug {
            import std.stdio;
            writeln(e.toString());
        }
        ownerTid.send("WORKER-FAILED~Exception thrown!");
    }
}

private void updateClientExecutableImpl(Client client, JSONValue payload) {
    import nectar_client.util : getNewExecutablePath, PATH_SEPARATOR;

    import std.base64 : Base64;
    import std.zlib : uncompress;
    import std.file : write, remove, exists;

    ubyte[] src = Base64.decode(payload["content"].str);
    ubyte[] uncompressed = cast(ubyte[]) uncompress(src); // Lots of memory used here

    string file = getNewExecutablePath(client.useSystemDirs) ~ PATH_SEPARATOR ~ "nectar-client-exec-new.bin";
    if(exists(file))
        remove(file);

    write(file, uncompressed);

    ownerTid.send("WORKER-SUCCESS~New executable saved to disk, restarting...");
}

private void setTimezoneImpl(Client client, JSONValue payload) {
    import nectar_client.util : convertTZLinuxToWindows, convertTZWindowsToLinux;

    version(linux) {
        // Use timedatectl on linux, std.process.execute
        auto result = execute(["timedatectl", "set-timezone", convertTZWindowsToLinux(payload["timezone"].str)]);

        if(result.status != 0) {
            ownerTid.send("WORKER-FAILED~timedatectl returned non-zero exit status: " ~ to!string(result.status));
            return;
        }

        ownerTid.send("WORKER-SUCCESS~timedatectl returned zero exit code (OK)");
        return;
    } else version(Windows) {
        // Use tzutil on Windows, std.process.execute
        auto result = execute(["tzutil", "/s", convertTZLinuxToWindows(payload["timzone"].str)]);

        if(result.status != 0) {
            ownerTid.send("WORKER-FAILED~tzutil returned non-zero exit status: " ~ to!string(result.status));
            return;
        }

        ownerTid.send("WORKER-SUCCESS~tzutil returned zero exit code (OK)");
        return;
    } else {
        assert(0, "Need to implement setTimezoneImpl for this platform!");
    }
}