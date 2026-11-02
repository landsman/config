// What record.ts would get wrong silently: Enter not meaning audio, a video
// saved as audio-only (or the reverse), a recording overwriting an earlier one
// of the same name, and the obsFile recording deleted when saving it failed — those
// last two lose a call — and the wrong Calendar event picked for it. ffmpeg is
// a stub on PATH that logs its arguments.
import { afterAll, beforeEach, expect, test } from "bun:test";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { callOfEachFile, chosenEvent, Mode, moveLooseCallsIntoFolders, recordingMode, requireFreeSpace, save } from "@bin/calls/record/record";
import { allRecordings } from "@bin/calls/transcribe/transcribe";

const testFolder = mkdtempSync(join(tmpdir(), "record-"));
const obsFile = join(testFolder, "2026-10-20_12-16-26.mkv");
const ffmpegLog = join(testFolder, "ffmpeg.ffmpegLog");
mkdirSync(join(testFolder, "bin"));
writeFileSync(join(testFolder, "bin", "ffmpeg"), `#!/bin/sh
echo "$*" >>"${ffmpegLog}"
[ -z "$FFMPEG_FAIL" ] || exit 1
for argument; do last=$argument; done; touch "$last"
`);
chmodSync(join(testFolder, "bin", "ffmpeg"), 0o755);
process.env.PATH = `${join(testFolder, "bin")}:${process.env.PATH}`;
const lastFfmpegArguments = () => readFileSync(ffmpegLog, "utf8").trim().split("\n").at(-1)!.replace(/.*-y /, "");

beforeEach(() => {
	writeFileSync(obsFile, "");
	delete process.env.FFMPEG_FAIL;
});
afterAll(() => rmSync(testFolder, { recursive: true }));

test("a disk with too little free space refuses to record, saying how much is free", () => {
	expect(() => requireFreeSpace(testFolder, 1e18)).toThrow(/GB free/);
	expect(() => requireFreeSpace(testFolder, 0)).not.toThrow();
});

test("Enter means audio", () => expect(recordingMode("")).toBe(Mode.Audio));
test("v means video", () => expect(recordingMode("v")).toBe(Mode.Video));
test("anything else is refused", () => expect(() => recordingMode("x")).toThrow());

test("audio is saved as .m4a, named date-name, keeping every audio track and no video", async () => {
	expect(await save(Mode.Audio, obsFile, `${testFolder}/out`, "Porada s Šárkou!")).toBe(`${testFolder}/out/20261020-porada-s-sarkou/20261020-porada-s-sarkou.m4a`);
	expect(lastFfmpegArguments()).toBe(`-i ${obsFile} -map 0:a -c copy ${testFolder}/out/20261020-porada-s-sarkou/20261020-porada-s-sarkou.m4a`);
});

test("the obsFile file goes once it is saved", async () => {
	await save(Mode.Audio, obsFile, `${testFolder}/out`, "gone");
	expect(existsSync(obsFile)).toBe(false);
});

test("a second recording of the same name gets -2, never overwrites", async () => {
	await save(Mode.Audio, obsFile, `${testFolder}/out`, "twice");
	writeFileSync(obsFile, "");
	expect(await save(Mode.Audio, obsFile, `${testFolder}/out`, "Twice")).toBe(`${testFolder}/out/20261020-twice-2/20261020-twice-2.m4a`);
});

test("no name means date and time", async () =>
	expect(await save(Mode.Audio, obsFile, `${testFolder}/out`, "")).toBe(`${testFolder}/out/20261020-12-16-26/20261020-12-16-26.m4a`));

test("video is saved as .mp4 and keeps everything", async () => {
	expect(await save(Mode.Video, obsFile, `${testFolder}/out`, "demo")).toBe(`${testFolder}/out/20261020-demo/20261020-demo.mp4`);
	expect(lastFfmpegArguments()).toBe(`-i ${obsFile} -map 0 -c copy ${testFolder}/out/20261020-demo/20261020-demo.mp4`);
});

test("a failed save fails and keeps the obsFile recording", async () => {
	process.env.FFMPEG_FAIL = "1";
	await expect(save(Mode.Audio, obsFile, `${testFolder}/out`, "x")).rejects.toThrow(obsFile);
	expect(existsSync(obsFile)).toBe(true);
});

test("Enter takes the best-fitting event, a number another, - none, anything else is asked again", () => {
	expect(chosenEvent("", ["a", "b"])).toBe("a");
	expect(chosenEvent("2", ["a", "b"])).toBe("b");
	expect(chosenEvent("-", ["a", "b"])).toBeUndefined();
	expect(() => chosenEvent("3", ["a", "b"])).toThrow();
	expect(() => chosenEvent("x", ["a", "b"])).toThrow();
});

test("a loose file goes to the call it is named after, X-2.txt to X unless X-2 is a call itself", () =>
	expect(Object.fromEntries(callOfEachFile([
		"20261021-sync.m4a", "20261021-sync.txt", "20261021-sync-2.txt", "20261021-sync.event.json",
		"20261020-demo.mp4", "20261020-demo-2.mp4", "20261020-demo-2.txt", "20261020-demo-3.txt",
		"notes.txt", "20261019-orphan.txt", ".DS_Store",
	]))).toEqual({
		"20261021-sync.m4a": "20261021-sync", "20261021-sync.txt": "20261021-sync",
		"20261021-sync-2.txt": "20261021-sync", "20261021-sync.event.json": "20261021-sync",
		"20261020-demo.mp4": "20261020-demo", "20261020-demo-2.mp4": "20261020-demo-2",
		"20261020-demo-2.txt": "20261020-demo-2", "20261020-demo-3.txt": "20261020-demo",
	}));

test("tidying moves loose calls into folders, twice is no change, and never over a file", () => {
	const folder = mkdtempSync(join(tmpdir(), "recordings-"));
	for (const file of ["a.m4a", "a.txt", "b.m4a", "notes.txt"]) {
		writeFileSync(join(folder, file), file);
	}
	mkdirSync(join(folder, "b"));
	writeFileSync(join(folder, "b", "b.m4a"), "already there");
	moveLooseCallsIntoFolders(folder);
	moveLooseCallsIntoFolders(folder);
	expect(readdirSync(join(folder, "a")).sort()).toEqual(["a.m4a", "a.txt"]);
	expect(readFileSync(join(folder, "b", "b.m4a"), "utf8")).toBe("already there");
	expect(readdirSync(folder).sort()).toEqual(["a", "b", "b.m4a", "notes.txt"]);
	expect(allRecordings(folder).map((recording) => recording.slice(folder.length + 1)).sort()).toEqual(["a/a.m4a", "b.m4a", "b/b.m4a"]);
	rmSync(folder, { recursive: true });
});
