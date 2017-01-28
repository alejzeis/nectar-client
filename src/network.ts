import * as net from "net";
import * as os from "os";

import * as client from "./client";

export class DaemonSocketHandler {
    private client: client.Client;
    private server: net.Server;

    constructor(client: client.Client) {
        this.client = client;

        this.server = net.createServer(this.newClient.bind(this));

        if(os.platform() === "win32") {
            // Use TCP socket on Windows
            this.server.listen({
                host: "127.0.0.1", // Listen only on loopback
                port: 42556
            });
        } else {
            // Use Unix socket
            this.server.listen(process.env.NECTAR_USE_SYSTEM ? "/var/run/nectar-clientd.socket" : process.cwd() + "/nectar-clientd.socket");
        }

        this.server.on("error", (error) => {
            this.client.logger.error("Error while running Daemon socket!");
            console.log(error);
            process.exit(1);
        });
    }

    public shutdown() {
        this.server.close();
    }

    private newClient(client: net.Socket) {

        this.client.logger.debug("New client connected to daemon socket.");
        client.on("data", this.clientDataHandler.bind(this));
        client.on("close", this.clientClose.bind(this));
    }

    private clientDataHandler(data: any) {
        // TODO
    }

    private clientClose(data: any) {
        this.client.logger.warn("Lost connection with frontend application.");
    }
}
