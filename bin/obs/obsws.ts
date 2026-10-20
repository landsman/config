#!/usr/bin/env bun
// Talk to OBS over its built-in obs-websocket (protocol v5).
//
// usage: obsws.ts enable                       turn the server on, keeping or making a password
//        obsws.ts <RequestType> [json] [field]  send one request, print its responseData
//                                               (or that one field of it)
import { createHash, randomBytes } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname } from "node:path";

const CONF = `${homedir()}/Library/Application Support/obs-studio/plugin_config/obs-websocket/config.json`;
const sha = (s: string) => createHash("sha256").update(s).digest("base64");

function enable() {
	const c = existsSync(CONF) ? JSON.parse(readFileSync(CONF, "utf8")) : {};
	Object.assign(c, { server_enabled: true, auth_required: true, alerts_enabled: false, first_load: false });
	c.server_port ??= 4455;
	c.server_password ||= randomBytes(18).toString("base64url");
	mkdirSync(dirname(CONF), { recursive: true });
	writeFileSync(CONF, JSON.stringify(c, null, 2));
}

function request(type: string, data: object): Promise<Record<string, unknown>> {
	const c = JSON.parse(readFileSync(CONF, "utf8"));
	const ws = new WebSocket(`ws://127.0.0.1:${c.server_port ?? 4455}`, "obswebsocket.json");
	const send = (op: number, d: object) => ws.send(JSON.stringify({ op, d }));
	return new Promise((resolve, reject) => {
		ws.onerror = () => reject(new Error("OBS does not answer"));
		ws.onclose = (e) => reject(new Error(`OBS closed the connection: ${e.reason}`));
		ws.onmessage = (e) => {
			const { op, d } = JSON.parse(String(e.data));
			if (op === 0) { // Hello: answer the password challenge, if OBS sets one
				const a = d.authentication;
				const auth = a && { authentication: sha(sha(c.server_password + a.salt) + a.challenge) };
				send(1, { rpcVersion: 1, eventSubscriptions: 0, ...auth });
			} else if (op === 2) { // Identified
				send(6, { requestType: type, requestId: "1", requestData: data });
			} else if (op === 7) { // RequestResponse
				ws.onclose = null;
				ws.close();
				const s = d.requestStatus;
				if (s.result) resolve(d.responseData ?? {});
				else reject(new Error(`${type} failed (${s.code}): ${s.comment ?? ""}`));
			}
		};
	});
}

const [cmd, json, field] = process.argv.slice(2);
if (cmd === "enable") {
	enable();
} else {
	try {
		const out = await request(cmd, json ? JSON.parse(json) : {});
		const v = field ? out[field] : out;
		console.log(v === undefined ? "" : typeof v === "string" ? v : JSON.stringify(v));
	} catch (e) {
		console.error(`obsws: ${(e as Error).message}`);
		process.exit(1);
	}
}
