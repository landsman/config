// OBS's built-in remote control, obs-websocket (protocol v5): turning it on,
// and one logged-in connection to send requests over.
import { createHash, randomBytes } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname } from "node:path";

const conf = `${homedir()}/Library/Application Support/obs-studio/plugin_config/obs-websocket/config.json`;

export type Call = (type: string, data?: object) => Promise<Record<string, any>>;

/** Server on, password kept or made. OBS rewrites this file on quit, so OBS must be closed. */
export function enable() {
	const c = existsSync(conf) ? JSON.parse(readFileSync(conf, "utf8")) : {};
	Object.assign(c, { server_enabled: true, auth_required: true, alerts_enabled: false, first_load: false });
	c.server_port ??= 4455;
	c.server_password ||= randomBytes(18).toString("base64url");
	mkdirSync(dirname(conf), { recursive: true });
	writeFileSync(conf, JSON.stringify(c, null, 2));
}

/** A connection logged in with the password enable() wrote. A failed request
 *  rejects with "<type> failed (<code>): <comment>". */
export function connect(): Promise<{ call: Call; close: () => void }> {
	const c = JSON.parse(readFileSync(conf, "utf8"));
	const ws = new WebSocket(`ws://127.0.0.1:${c.server_port ?? 4455}`, "obswebsocket.json");
	const sha = (s: string) => createHash("sha256").update(s).digest("base64");
	const send = (op: number, d: object) => ws.send(JSON.stringify({ op, d }));
	const pending = new Map<string, [(v: any) => void, (e: Error) => void, string]>();
	let id = 0;
	return new Promise((resolve, reject) => {
		const lost = (why: string) => {
			reject(new Error(why));
			for (const [, [, rej]] of pending) rej(new Error(why));
		};
		ws.onerror = () => lost("OBS does not answer");
		ws.onclose = (e) => lost(`OBS closed the connection ${e.reason}`);
		ws.onmessage = (e) => {
			const { op, d } = JSON.parse(String(e.data));
			if (op === 0) { // Hello: answer the password challenge, if OBS sets one
				const a = d.authentication;
				const auth = a && { authentication: sha(sha(c.server_password + a.salt) + a.challenge) };
				send(1, { rpcVersion: 1, eventSubscriptions: 0, ...auth });
			} else if (op === 2) { // Identified
				resolve({
					call: (type, data = {}) => new Promise((res, rej) => {
						const requestId = String(++id);
						pending.set(requestId, [res, rej, type]);
						send(6, { requestType: type, requestId, requestData: data });
					}),
					close: () => { ws.onclose = null; ws.close(); },
				});
			} else if (op === 7) { // RequestResponse
				const [res, rej, type] = pending.get(d.requestId)!;
				pending.delete(d.requestId);
				const s = d.requestStatus;
				s.result ? res(d.responseData ?? {}) : rej(new Error(`${type} failed (${s.code}): ${s.comment ?? ""}`));
			}
		};
	});
}
