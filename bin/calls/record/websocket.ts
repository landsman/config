// OBS's built-in remote control, obs-websocket (protocol v5): turning it on,
// and one logged-in connection to send requests over.
import { createHash, randomBytes } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname } from "node:path";
import { match } from "ts-pattern";

const settingsFile = `${homedir()}/Library/Application Support/obs-studio/plugin_config/obs-websocket/config.json`;
const defaultPort = 4455;

export type Call = (requestType: string, requestData?: object) => Promise<Record<string, any>>;

/** Server on, password kept or made. OBS rewrites this file on quit, so OBS must be closed. */
export function enable() {
	const settings = existsSync(settingsFile) ? JSON.parse(readFileSync(settingsFile, "utf8")) : {};
	Object.assign(settings, {
		server_enabled: true,
		auth_required: true,
		alerts_enabled: false,
		first_load: false,
	});
	settings.server_port ??= defaultPort;
	settings.server_password ||= randomBytes(18).toString("base64url");
	mkdirSync(dirname(settingsFile), { recursive: true });
	writeFileSync(settingsFile, JSON.stringify(settings, null, 2));
}

/** What each message on the connection is, by its op code in the protocol. */
enum OpCode {
	Hello = 0,
	Identify = 1,
	Identified = 2,
	Request = 6,
	RequestResponse = 7,
}

type WaitingRequest = {
	requestType: string;
	answer: (responseData: Record<string, any>) => void;
	fail: (error: Error) => void;
};

/** A connection logged in with the password enable() wrote. A failed request
 *  rejects with "<type> failed (<code>): <comment>". */
export function connect(): Promise<{ call: Call; close: () => void }> {
	const settings = JSON.parse(readFileSync(settingsFile, "utf8"));
	const socket = new WebSocket(`ws://127.0.0.1:${settings.server_port ?? defaultPort}`, "obswebsocket.json");
	const send = (opCode: OpCode, data: object) => {
		socket.send(JSON.stringify({ op: opCode, d: data }));
	};
	const waiting = new Map<string, WaitingRequest>();
	let lastRequestId = 0;

	const call: Call = (requestType, requestData = {}) => {
		return new Promise((answer, fail) => {
			const requestId = String(++lastRequestId);
			waiting.set(requestId, { requestType, answer, fail });
			send(OpCode.Request, { requestType, requestId, requestData });
		});
	};
	const close = () => {
		socket.onclose = null;
		socket.close();
	};

	return new Promise((connected, failed) => {
		const lost = (reason: string) => {
			failed(new Error(reason));
			for (const request of waiting.values()) {
				request.fail(new Error(reason));
			}
		};
		socket.onerror = () => lost("OBS does not answer");
		socket.onclose = (closing) => lost(`OBS closed the connection ${closing.reason}`);
		socket.onmessage = (message) => {
			const { op: opCode, d: data } = JSON.parse(String(message.data));
			match(opCode)
				.with(OpCode.Hello, () => {
					send(OpCode.Identify, {
						rpcVersion: 1,
						eventSubscriptions: 0,
						...passwordAnswer(settings.server_password, data.authentication),
					});
				})
				.with(OpCode.Identified, () => {
					connected({ call, close });
				})
				.with(OpCode.RequestResponse, () => {
					const request = waiting.get(data.requestId);
					if (!request) {
						return;
					}
					waiting.delete(data.requestId);
					const status = data.requestStatus;
					if (status.result) {
						request.answer(data.responseData ?? {});
					} else {
						request.fail(new Error(`${request.requestType} failed (${status.code}): ${status.comment ?? ""}`));
					}
				})
				// The op code comes from OBS: events and anything newer in the protocol are not asked for.
				.otherwise(() => {});
		};
	});
}

/** The answer to OBS's password challenge, when it sets one: sha256 of the password with its
 *  salt, then of that with the challenge, both base64. */
function passwordAnswer(password: string, challenge?: { salt: string; challenge: string }) {
	if (!challenge) {
		return {};
	}
	const base64Sha256 = (text: string) => createHash("sha256").update(text).digest("base64");
	const secret = base64Sha256(password + challenge.salt);
	return { authentication: base64Sha256(secret + challenge.challenge) };
}
