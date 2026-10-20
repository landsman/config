#!/usr/bin/env bun
// Records a call (Google Meet or any other) with OBS without touching its audio:
// what the Mac plays is tapped through ScreenCaptureKit and the mic is read as
// it is, so the call app keeps its own devices and nobody hears a difference.
// The whole Mac rather than one app, so it works whatever the call runs in;
// mute notifications during a call, they get recorded too.
//
// OBS is driven over its built-in websocket; its profiles and scenes are files
// in config/. Tracks: 1 = both mixed, 2 = the call, 3 = my mic; a player plays
// the first. In the scenes, "mixers" is a bitmask of the tracks a source feeds:
// 3 = 1+2, 5 = 1+3.
//
// usage: record.ts setup               install OBS and set it up (quits OBS first)
//        record.ts start [audio|video] asks which when not given, Enter = audio
//        record.ts stop [name]         stop, ask for a name when not given (Enter = the
//                                      time), save to ~/Recordings, print the path
import { $ } from "bun";
import { createHash, randomBytes } from "node:crypto";
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";

type Mode = "audio" | "video";

const here = import.meta.dir;
const conf = `${homedir()}/Library/Application Support/obs-studio`;
const wsConf = `${conf}/plugin_config/obs-websocket/config.json`;
const out = process.env.RECORDINGS_DIR ?? `${homedir()}/Recordings`;
const obsPattern = "OBS.app/Contents/MacOS/OBS$";

// Styled and indented only on a terminal: the saved path is also read by
// scripts, $(…), and has to arrive bare. stdout and stderr are asked apart.
const tty = { out: !!process.stdout.isTTY, err: !!process.stderr.isTTY };
const style = (on: boolean, sgr: string) => (t: string) => (on ? `\x1b[${sgr}m${t}\x1b[0m` : t);
const o = { bold: style(tty.out, "1"), dim: style(tty.out, "2"), red: style(tty.out, "1;31"), green: style(tty.out, "1;32") };
const e = { bold: style(tty.err, "1"), dim: style(tty.err, "2"), red: style(tty.err, "1;31"), cyan: style(tty.err, "1;36") };
const say = (...lines: string[]) => { for (const l of lines) console.log(tty.out ? `  ${l}` : l); };
// process.stderr.write, not console.error: Bun colours that one red on its own.
const warn = (text: string) => process.stderr.write(`${tty.err ? "  " : ""}${e.red(`✗ ${text}`)}\n`);
// A terminal link (OSC 8), so ⌘-click opens the file whatever the terminal makes of a bare path.
const link = (path: string) =>
	tty.out ? `\x1b]8;;file://${encodeURI(path)}\x1b\\${path}\x1b]8;;\x1b\\` : path;

async function ask(question: string, hint: string): Promise<string> {
	process.stderr.write(`${tty.err ? "  " : ""}${e.cyan("?")} ${e.bold(question)} ${e.dim(hint)} ${e.cyan("›")} `);
	for await (const line of console) return line.trim();
	return "";
}

// "12.3 MB · 4:05", for the line that says what was saved.
async function describe(path: string): Promise<string> {
	const mb = (statSync(path).size / 1e6).toFixed(1);
	const s = Math.round(Number(await $`ffprobe -v error -show_entries format=duration -of csv=p=0 ${path}`.nothrow().text()) || 0);
	return `${mb} MB · ${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

export function mode(answer = ""): Mode {
	if (["", "a", "audio"].includes(answer)) return "audio";
	if (["v", "video"].includes(answer)) return "video";
	throw new Error(`audio or video, not '${answer}'`);
}

// "Porada s Šárkou" -> porada-s-sarkou
export const slug = (name: string) =>
	name.normalize("NFKD").replace(/[^\x00-\x7f]/g, "").toLowerCase()
		.replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

// <dir>/YYYYMMDD-<name>.m4a|mp4, the time when there is no name, and never over
// an earlier file. raw is named by config/'s FilenameFormatting: 2026-10-20_12-16-26.
export function target(m: Mode, raw: string, dir: string, name: string): string {
	const stamp = basename(raw).replace(/\.[^.]*$/, "");
	const base = `${stamp.slice(0, 10).replaceAll("-", "")}-${slug(name) || stamp.slice(11)}`;
	const ext = m === "video" ? "mp4" : "m4a";
	let dst = join(dir, `${base}.${ext}`);
	for (let i = 2; existsSync(dst); i++) dst = join(dir, `${base}-${i}.${ext}`);
	return dst;
}

// Audio keeps every audio track and drops the black frame; video keeps all.
// The raw file goes only once the copy is saved: it is the call.
export async function save(m: Mode, raw: string, dir: string, name: string): Promise<string> {
	const dst = target(m, raw, dir, name);
	mkdirSync(dir, { recursive: true });
	const map = m === "video" ? ["-map", "0"] : ["-map", "0:a"];
	const r = await $`ffmpeg -nostdin -loglevel error -y -i ${raw} ${map} -c copy ${dst}`.nothrow();
	if (r.exitCode !== 0) throw new Error(`saving failed, the recording is still at ${raw}`);
	await $`rm ${raw}`;
	return dst;
}

const running = async (pattern: string) => (await $`pgrep -qf ${pattern}`.nothrow().quiet()).exitCode === 0;
const sleep = (s: number) => Bun.sleep(s * 1000);

type Call = (type: string, data?: object) => Promise<Record<string, any>>;

// One obs-websocket (protocol v5) connection, logged in with the password setup made.
function connect(): Promise<{ call: Call; close: () => void }> {
	const c = JSON.parse(readFileSync(wsConf, "utf8"));
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

function enableWebsocket() {
	const c = existsSync(wsConf) ? JSON.parse(readFileSync(wsConf, "utf8")) : {};
	Object.assign(c, { server_enabled: true, auth_required: true, alerts_enabled: false, first_load: false });
	c.server_port ??= 4455;
	c.server_password ||= randomBytes(18).toString("base64url");
	mkdirSync(dirname(wsConf), { recursive: true });
	writeFileSync(wsConf, JSON.stringify(c, null, 2));
}

async function setup() {
	if (!existsSync("/Applications/OBS.app")) await $`brew install --cask obs`;
	if (await running(obsPattern)) {
		if (await running("obs-ffmpeg-mux")) throw new Error("OBS is recording, stop it first");
		// OBS rewrites its config on quit, so it has to be closed while this writes.
		await $`osascript -e ${'tell application "OBS" to quit'}`.nothrow().quiet();
		for (let i = 0; i < 20 && (await running(obsPattern)); i++) await sleep(1);
		if (await running(obsPattern))
			throw new Error("OBS did not quit, a window in it may be open: close it, quit OBS, run this again");
	}
	mkdirSync(`${out}/.obs`, { recursive: true });
	// config/ mirrors OBS's own folder. Copied, not stowed: OBS replaces a
	// symlink with a file when it saves. user.ini only on a fresh install.
	for (const f of readdirSync(`${here}/config`, { recursive: true, encoding: "utf8" })) {
		const src = `${here}/config/${f}`, dst = `${conf}/${f}`;
		if (statSync(src).isDirectory() || (f === "user.ini" && existsSync(dst))) continue;
		mkdirSync(dirname(dst), { recursive: true });
		writeFileSync(dst, readFileSync(src, "utf8").replaceAll("@RECORDINGS@", out));
	}
	enableWebsocket();
	say(`${o.green("✓")} ${o.bold("OBS is set up")}`,
		o.dim("  On its first start macOS asks for Microphone and Screen Recording: allow both."));
}

async function start(answer?: string) {
	const m = mode(answer ?? (await ask("Record audio or video?", "[Enter = audio]")));
	if (!existsSync(`${conf}/basic/profiles/MeetVideo/basic.ini`)) await setup();
	if (!(await running(obsPattern))) await $`open -g -a OBS`;
	let obs;
	for (let i = 0; !obs; i++) {
		obs = await connect().catch(() => undefined);
		if (!obs && i >= 30) throw new Error("OBS does not answer: is a dialog open in its window?");
		if (!obs) await sleep(1);
	}
	const { call, close } = obs;
	// Connected is not ready: right after launch OBS answers 207 for a few seconds.
	for (let i = 0; ; i++) {
		const ready = await call("GetSceneCollectionList").then(() => true, (e: Error) => {
			if (!e.message.includes("(207)") || i >= 30) throw e;
			return false;
		});
		if (ready) break;
		await sleep(1);
	}
	// The answer comes from OBS itself, so a setting changed by hand in its window wins.
	const use = async (list: string, current: string, set: string, field: string, value: string) => {
		if ((await call(list))[current] === value) return;
		await call(set, { [field]: value });
		await sleep(1);
	};
	await use("GetSceneCollectionList", "currentSceneCollectionName", "SetCurrentSceneCollection", "sceneCollectionName", "MeetCall");
	if (m === "video") {
		await use("GetProfileList", "currentProfileName", "SetCurrentProfile", "profileName", "MeetVideo");
		// The display's id differs per Mac, so config/ cannot carry it. Read from
		// macOS: asking OBS for its display list crashes it (32.2).
		const display = (await $`osascript -l JavaScript ${`${here}/display.js`}`.text()).trim();
		await call("SetInputSettings", { inputName: "Display", inputSettings: { display_uuid: display } });
		await call("SetCurrentProgramScene", { sceneName: "Screen" });
	} else {
		await use("GetProfileList", "currentProfileName", "SetCurrentProfile", "profileName", "MeetAudio");
		await call("SetCurrentProgramScene", { sceneName: "Audio" });
	}
	await call("StartRecord");
	close();
	say(`${o.red("●")} ${o.bold(`Recording ${m}`)}`, o.dim("  Stop it with  make record-stop"));
}

async function stop(name?: string) {
	name ??= await ask("Name the recording", "[Enter = the time]");
	const { call, close } = await connect();
	const { currentProfileName } = await call("GetProfileList");
	const { outputPath } = await call("StopRecord");
	close();
	// StopRecord answers before the muxer has closed the file.
	for (let i = 0; i < 30 && (await running("obs-ffmpeg-mux")); i++) await sleep(1);
	const saved = await save(currentProfileName === "MeetVideo" ? "video" : "audio", outputPath, out, name);
	if (!tty.out) return say(saved); // a script reading it gets the path alone
	say(`${o.green("✓")} ${o.bold(`Saved ${basename(saved)}`)}  ${o.dim(await describe(saved))}`, `  ${link(saved)}`);
}

if (import.meta.main) {
	const [cmd, arg] = process.argv.slice(2);
	const commands: Record<string, () => Promise<void>> = {
		setup, start: () => start(arg || undefined), stop: () => stop(arg || undefined),
	};
	try {
		if (!commands[cmd]) {
			console.error(readFileSync(import.meta.path, "utf8").match(/^\/\/ usage:[\s\S]*?(?=^import)/m)![0].replace(/^\/\/ ?/gm, ""));
			process.exit(2);
		}
		await commands[cmd]();
	} catch (e) {
		warn((e as Error).message);
		process.exit(1);
	}
}
