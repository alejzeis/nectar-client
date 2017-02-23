import * as request from "request";
import * as jsonwebtoken from "jsonwebtoken";

import * as fs from "fs";
import * as os from "os";

import * as client from "./client";

export function tryDeploymentJoin(c: client.Client, cb: (success: boolean)=>void) {
    request(c.nectarAddressFull + "deploy/deployJoin", (error, response, body) => {
        // TODO: try deploy join, call cb
    });
}
