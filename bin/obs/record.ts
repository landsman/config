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
//        record.ts start [audio|video] asks which when not given (Enter = audio), then
//                                      waits with a clock: Ctrl+C or q stops and saves
//        record.ts stop [name]         stop, ask for a name when not given (Enter = the
//                                      time), save to ~/Recordings, print the path; for a
//                                      recording whose terminal was closed
import { $ } from "bun";
import { existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import { cli } from "@lib/cli";
import { copyTree } from "@lib/files";
import { describe } from "@lib/media";
import { retry, running, waitFor } from "@lib/proc";
import { ask, done, hint, link, live, o, say, untilKey } from "@lib/term";
import { slug } from "@lib/text";
import { connect, enable } from "./websocket";

type Mode = "audio" | "video";

const here = import.meta.dir;
const conf = `${homedir()}/Library/Application Support/obs-studio`;
const out = process.env.RECORDINGS_DIR ?? `${homedir()}/Recordings`;
const obsPattern = "OBS.app/Contents/MacOS/OBS$";

export function mode(answer = ""): Mode {
	if (["", "a", "audio"].includes(answer)) return "audio";
	if (["v", "video"].includes(answer)) return "video";
	throw new Error(`audio or video, not '${answer}'`);
}

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

async function setup() {
	if (!existsSync("/Applications/OBS.app")) await $`brew install --cask obs`;
	if (await running(obsPattern)) {
		if (await running("obs-ffmpeg-mux")) throw new Error("OBS is recording, stop it first");
		// OBS rewrites its config on quit, so it has to be closed while this writes.
		await $`osascript -e ${'tell application "OBS" to quit'}`.nothrow().quiet();
		if (!(await waitFor(async () => !(await running(obsPattern)), 20)))
			throw new Error("OBS did not quit, a window in it may be open: close it, quit OBS, run this again");
	}
	mkdirSync(`${out}/.obs`, { recursive: true });
	// config/ mirrors OBS's own folder. Copied, not stowed: OBS replaces a
	// symlink with a file when it saves. user.ini only on a fresh install.
	copyTree(`${here}/config`, conf, { "@RECORDINGS@": out }, ["user.ini"]);
	enable();
	done("OBS is set up");
	hint("On its first start macOS asks for Microphone and Screen Recording: allow both.");
}

async function start(answer?: string) {
	const m = mode(answer ?? (await ask("Record audio or video?", "[Enter = audio]")));
	if (!existsSync(`${conf}/basic/profiles/MeetVideo/basic.ini`)) await setup();
	if (!(await running(obsPattern))) await $`open -g -a OBS`;
	const { call, close } = await retry(connect, 30).catch(() => {
		throw new Error("OBS does not answer: is a dialog open in its window?");
	});
	// Connected is not ready: right after launch OBS answers 207 for a few seconds.
	await retry(() => call("GetSceneCollectionList"), 30, (e) => e.message.includes("(207)"));
	// The answer comes from OBS itself, so a setting changed by hand in its window wins.
	const use = async (list: string, current: string, set: string, field: string, value: string) => {
		if ((await call(list))[current] === value) return;
		await call(set, { [field]: value });
		await Bun.sleep(1000);
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
	if (!process.stdin.isTTY || !process.stdout.isTTY) {
		live(`Recording ${m}`);
		return hint("Stop it with  make record-stop");
	}
	// Waits here with a running clock; Ctrl+C or q stops and saves. Closing the
	// terminal leaves OBS recording, for `make record-stop` to finish.
	const t0 = Date.now();
	const clock = () => {
		const s = Math.floor((Date.now() - t0) / 1000);
		return `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
	};
	process.stdout.write("\n");
	hint("Ctrl+C stops and saves  ·  closing the terminal keeps it recording, for  make record-stop");
	await untilKey(["\x03", "q"], () =>
		process.stdout.write(`\x1b[2A\r\x1b[K  ${o.red("●")} ${o.bold(`Recording ${m}`)}  ${o.dim(clock())}\x1b[2B\r`));
	await stop();
}

async function stop(name?: string) {
	name ??= await ask("Name the recording", "[Enter = the time]");
	const { call, close } = await connect();
	const { currentProfileName } = await call("GetProfileList");
	const { outputPath } = await call("StopRecord");
	close();
	// StopRecord answers before the muxer has closed the file.
	await waitFor(async () => !(await running("obs-ffmpeg-mux")), 30);
	const saved = await save(currentProfileName === "MeetVideo" ? "video" : "audio", outputPath, out, name);
	if (!process.stdout.isTTY) return say(saved); // a script reading it gets the path alone
	done(`Saved ${basename(saved)}`, await describe(saved));
	say(`  ${link(saved)}  ${o.dim("⌘ + click to open")}`);
}

if (import.meta.main) await cli(import.meta.path, { setup, start, stop });
