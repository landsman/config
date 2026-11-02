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
// usage: record.ts setup               install OBS and set it up (quits OBS first), and move
//                                      calls saved loose in ~/Recordings into a folder each
//        record.ts start [audio|video] asks which when not given (Enter = audio), then
//                                      waits with a clock: Ctrl+C or q stops and saves
//        record.ts stop [name]         stop, ask for a name when not given (Enter = the
//                                      Calendar event at that time, or the time), save to
//                                      ~/Recordings/<name>/ with the event beside it as <name>.event.json
//                                      for the transcript, print the path; for a
//                                      recording whose terminal was closed; then
//                                      offers to transcribe it, see ../transcribe/transcribe.ts
import { $ } from "bun";
import { existsSync, mkdirSync, readdirSync, renameSync, statfsSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";
import { cli } from "@lib/cli";
import { copyTree } from "@lib/files";
import { describe } from "@lib/media";
import { retry, running, waitFor } from "@lib/proc";
import { ask, askUntil, done, gap, hint, link, live, o, say, untilKey } from "@lib/term";
import { slug } from "@lib/text";
import { eventFilePath } from "@bin/calls/calendar/event";
import { type CallEvent, eventsDuring } from "@bin/calls/macos/calendar";
import { connect, enable } from "@bin/calls/record/websocket";
import { fileInBrain, transcribe } from "@bin/calls/transcribe/transcribe";

export enum Mode {
	Audio = "audio",
	Video = "video",
}

const thisFolder = import.meta.dir;
const obsSettingsFolder = `${homedir()}/Library/Application Support/obs-studio`;
const recordingsFolder = process.env.RECORDINGS_DIR ?? `${homedir()}/Recordings`;
const obsProcess = "OBS.app/Contents/MacOS/OBS$";
const obsSavingProcess = "obs-ffmpeg-mux";

/** Audio or video, as answered: Enter or a is audio, v is video. */
export function recordingMode(answer = ""): Mode {
	if (["", "a", "audio"].includes(answer)) {
		return Mode.Audio;
	}
	if (["v", "video"].includes(answer)) {
		return Mode.Video;
	}
	throw new Error(`audio or video, not '${answer}'`);
}

async function start(answer?: string) {
	requireFreeSpace(existsSync(recordingsFolder) ? recordingsFolder : homedir());
	gap();
	const mode = answer === undefined
		? await askUntil("Record audio or video?", "[Enter or a = audio, v = video]", recordingMode)
		: recordingMode(answer);
	if (!existsSync(`${obsSettingsFolder}/basic/profiles/MeetVideo/basic.ini`)) {
		await setup();
	}

	// -j: started hidden, it only has to record; stop() quits it again.
	if (!(await running(obsProcess))) {
		await $`open -g -j -a OBS`;
	}
	const { call, close } = await retry(connect, 30).catch(() => {
		throw new Error("OBS does not answer: is a dialog open in its window?");
	});
	// Connected is not ready: right after launch OBS answers 207 for a few seconds.
	await retry(
		() => call("GetSceneCollectionList"),
		30,
		(error) => error.message.includes("(207)"),
	);

	// The answer comes from OBS itself, so a setting changed by hand in its window wins.
	const switchTo = async (setting: ObsSetting, value: string) => {
		const current = await call(setting.listRequest);
		if (current[setting.currentField] === value) {
			return;
		}
		await call(setting.setRequest, { [setting.valueField]: value });
		await Bun.sleep(1000);
	};
	await switchTo(sceneCollection, "MeetCall");
	if (mode === Mode.Video) {
		await switchTo(profile, "MeetVideo");
		// The display's id differs per Mac, so config/ cannot carry it. Read from
		// macOS: asking OBS for its display list crashes it (32.2).
		const displayScript = `${thisFolder}/../macos/display.js`;
		const displayId = (await $`osascript -l JavaScript ${displayScript}`.text()).trim();
		await call("SetInputSettings", { inputName: "Display", inputSettings: { display_uuid: displayId } });
		await call("SetCurrentProgramScene", { sceneName: "Screen" });
	} else {
		await switchTo(profile, "MeetAudio");
		await call("SetCurrentProgramScene", { sceneName: "Audio" });
	}
	await call("StartRecord");
	close();

	if (!process.stdin.isTTY || !process.stdout.isTTY) {
		gap();
		live(`Recording ${mode}`);
		hint("Stop it with  make record-stop");
		return gap();
	}
	await waitWithClock(mode);
	await stop();
}

/** A setting OBS keeps a list of, with the requests that read and change it. */
type ObsSetting = { listRequest: string; currentField: string; setRequest: string; valueField: string };

const sceneCollection: ObsSetting = {
	listRequest: "GetSceneCollectionList",
	currentField: "currentSceneCollectionName",
	setRequest: "SetCurrentSceneCollection",
	valueField: "sceneCollectionName",
};

const profile: ObsSetting = {
	listRequest: "GetProfileList",
	currentField: "currentProfileName",
	setRequest: "SetCurrentProfile",
	valueField: "profileName",
};

/** Waits here with a running clock; Ctrl+C or q stops and saves. Closing the terminal
 *  leaves OBS recording, for `make record-stop` to finish. */
async function waitWithClock(mode: Mode) {
	const startedAt = Date.now();
	const elapsed = () => {
		const seconds = Math.floor((Date.now() - startedAt) / 1000);
		const minutes = String(Math.floor(seconds / 60)).padStart(2, "0");
		return `${minutes}:${String(seconds % 60).padStart(2, "0")}`;
	};
	gap();
	process.stdout.write("\n"); // the clock's line, drawn by redrawClock below
	hint("Ctrl+C stops and saves");
	hint("Closing the terminal keeps it recording; finish it with  make record-stop");
	const redrawClock = () => {
		const clockLine = `  ${o.red("●")} ${o.bold(`Recording ${mode}`)}  ${o.dim(elapsed())}`;
		process.stdout.write(`\x1b[3A\r\x1b[K${clockLine}\x1b[3B\r`);
	};
	const ctrlC = "\x03";
	await untilKey([ctrlC, "q"], redrawClock);
}

/** Refuses to start when the disk is nearly full: OBS keeps recording into a full disk
 *  and the call is lost, noticed only at the end. 10 GB is hours of video. */
export function requireFreeSpace(folder: string, neededBytes = 10e9) {
	const { bavail: freeBlocks, bsize: blockSize } = statfsSync(folder);
	const freeBytes = freeBlocks * blockSize;
	if (freeBytes < neededBytes) {
		const free = (freeBytes / 1e9).toFixed(1);
		throw new Error(`only ${free} GB free on the disk, ${neededBytes / 1e9} GB needed to record: free some space first`);
	}
}

async function stop(name?: string) {
	gap();
	const { call, close } = await connect();
	// The event is looked up while OBS still knows how long it has been recording.
	const { outputDuration } = await call("GetRecordStatus");
	const callStart = new Date(Date.now() - outputDuration);
	const event = await pickEvent(eventsDuring(callStart, new Date()));
	if (name === undefined) {
		const answer = await ask("Name the recording", `[Enter = ${event?.title || "the time"}]`);
		name = answer || event?.title || "";
	}
	const { currentProfileName } = await call("GetProfileList");
	const { outputPath: obsFile } = await call("StopRecord");
	close();

	// StopRecord answers before the file is closed.
	await waitFor(async () => !(await running(obsSavingProcess)), 30);
	await quitObs().catch(() => {}); // a window left open in it only keeps it running
	const mode = currentProfileName === "MeetVideo" ? Mode.Video : Mode.Audio;
	const saved = await save(mode, obsFile, recordingsFolder, name);
	if (event) {
		await Bun.write(eventFilePath(saved), `${JSON.stringify(event, null, "\t")}\n`);
	}

	if (!process.stdout.isTTY) {
		return say(saved); // a script reading it gets the path alone
	}
	gap();
	done(`Saved ${basename(saved)}`, await describe(saved));
	say(`  ${link(saved)}`);
	hint("⌘ + click to open");
	gap();
	if (!process.stdin.isTTY) {
		return;
	}
	const wantsTranscript = await ask("Transcribe it?", "[y/N]");
	if (!["y", "yes"].includes(wantsTranscript.toLowerCase())) {
		return;
	}
	const transcript = await transcribe(saved);
	gap();
	done(`Transcribed ${basename(transcript)}`);
	say(`  ${link(transcript)}`);
	hint("⌘ + click to open");
	gap();
	await fileInBrain(transcript);
}

/** The event the call was, asked only when Calendar has more than one at that time. */
async function pickEvent(events: CallEvent[]): Promise<CallEvent | undefined> {
	if (events.length < 2 || !process.stdin.isTTY) {
		return events[0];
	}
	const choices = events
		.map((event, index) => `${index + 1} = ${event.title || "untitled"}`)
		.join(", ");
	return askUntil(
		"Which event was the call?",
		`[Enter = 1, ${choices}, - = none]`,
		(answer) => chosenEvent(answer, events),
	);
}

/** Enter is the first, a number is that one, "-" is none. */
export function chosenEvent<Event>(answer: string, events: Event[]): Event | undefined {
	if (answer === "-") {
		return undefined;
	}
	const index = answer === "" ? 0 : Number(answer) - 1;
	if (!Number.isInteger(index) || !events[index]) {
		throw new Error(`a number from 1 to ${events.length}, or -`);
	}
	return events[index];
}

// Audio keeps every audio track and drops the black frame; video keeps all.
// The file OBS wrote goes only once the copy is saved: it is the call.
export async function save(mode: Mode, obsFile: string, folder: string, name: string): Promise<string> {
	const recording = recordingPath(mode, obsFile, folder, name);
	mkdirSync(dirname(recording), { recursive: true });
	const streams = mode === Mode.Video ? ["-map", "0"] : ["-map", "0:a"];
	const copied = await $`ffmpeg -nostdin -loglevel error -y -i ${obsFile} ${streams} -c copy ${recording}`.nothrow();
	if (copied.exitCode !== 0) {
		throw new Error(`saving failed, the recording is still at ${obsFile}`);
	}
	await $`rm ${obsFile}`;
	return recording;
}

// <folder>/YYYYMMDD-<name>/YYYYMMDD-<name>.m4a|mp4: a folder per call, for the event and
// transcripts saved beside it, and each file still named after the call wherever it is
// copied. The time when there is no name, and never into an earlier call's folder.
// OBS names its file by config/'s FilenameFormatting: 2026-10-20_12-16-26.
export function recordingPath(mode: Mode, obsFile: string, folder: string, name: string): string {
	const startedAt = basename(obsFile).replace(/\.[^.]*$/, "");
	const date = startedAt.slice(0, 10).replaceAll("-", "");
	const time = startedAt.slice(11);
	const callName = `${date}-${slug(name) || time}`;
	const extension = mode === Mode.Video ? "mp4" : "m4a";

	let callFolder = callName;
	for (let copy = 2; existsSync(join(folder, callFolder)); copy++) {
		callFolder = `${callName}-${copy}`;
	}
	return join(folder, callFolder, `${callFolder}.${extension}`);
}

/** Quits OBS and waits until it is gone; refuses while it records. */
async function quitObs() {
	if (!(await running(obsProcess))) {
		return;
	}
	if (await running(obsSavingProcess)) {
		throw new Error("OBS is recording, stop it first");
	}
	await $`osascript -e ${'tell application "OBS" to quit'}`.nothrow().quiet();
	const quit = await waitFor(async () => !(await running(obsProcess)), 20);
	if (!quit) {
		throw new Error("OBS did not quit, a window in it may be open: close it, quit OBS, run this again");
	}
}

async function setup() {
	if (!existsSync("/Applications/OBS.app")) {
		await $`brew install --cask obs`;
	}
	// OBS rewrites its config on quit, so it has to be closed while this writes.
	await quitObs();
	mkdirSync(`${recordingsFolder}/.obs`, { recursive: true });
	// config/ mirrors OBS's own folder. Copied, not stowed: OBS replaces a
	// symlink with a file when it saves. user.ini only on a fresh install.
	copyTree(`${thisFolder}/config`, obsSettingsFolder, { "@RECORDINGS@": recordingsFolder }, ["user.ini"]);
	enable();
	done("OBS is set up");
	hint("On its first start macOS asks for Microphone and Screen Recording: allow both.");
	moveLooseCallsIntoFolders(recordingsFolder);
}

/** Moves the calls saved before they got a folder each into one. Run again it finds nothing,
 *  and it never moves over a file: a clash stays where it is. */
export function moveLooseCallsIntoFolders(folder: string) {
	if (!existsSync(folder)) {
		return;
	}
	const looseFiles = readdirSync(folder).filter((file) => statSync(join(folder, file)).isFile());
	let moved = 0;
	for (const [file, callName] of callOfEachFile(looseFiles)) {
		const destination = join(folder, callName, file);
		if (existsSync(destination)) {
			continue;
		}
		mkdirSync(join(folder, callName), { recursive: true });
		renameSync(join(folder, file), destination);
		moved++;
	}
	if (moved) {
		done(`Moved ${moved} files into a folder per call`, folder);
	}
}

/** Which call's folder each loose file goes to: a recording to its own, and its transcripts
 *  and event to the recording they are named after. X-2.txt is X's second transcript, unless
 *  X-2 is a recording of its own. Anything else stays out. */
export function callOfEachFile(files: string[]): Map<string, string> {
	const withoutExtension = (file: string) => file.replace(/\.[^.]*$/, "");
	const recordings = new Set(
		files
			.filter((file) => /\.(m4a|mp4)$/.test(file))
			.map(withoutExtension),
	);
	const callByFile = new Map<string, string>();
	for (const file of files) {
		const sameName = file.match(/^(.*)\.(m4a|mp4|txt|event\.json)$/)?.[1];
		const laterTranscriptOf = file.match(/^(.*)-\d+\.txt$/)?.[1];
		if (sameName && recordings.has(sameName)) {
			callByFile.set(file, sameName);
		} else if (laterTranscriptOf && recordings.has(laterTranscriptOf)) {
			callByFile.set(file, laterTranscriptOf);
		}
	}
	return callByFile;
}

if (import.meta.main) {
	await cli(import.meta.path, { setup, start, stop });
}
