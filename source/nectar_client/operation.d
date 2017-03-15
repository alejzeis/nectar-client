module nectar_client.operation;

import std.json;
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
    switch(operation.id) {
        case OperationID.OPERATION_SET_TIMEZONE:
            setTimezoneImpl(cast(Client) client, operation.payload);
            break;
        default:
            ownerTid.send("WORKER-FAILED~The operation given is unknown or not implemented.");
            return;
    }
}

private void setTimezoneImpl(Client client, JSONValue payload) {
    // TODO: set timezone
}