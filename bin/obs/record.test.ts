// What record.ts would get wrong silently: Enter not meaning audio, a video
// saved as audio-only (or the reverse), a recording overwriting an earlier one
// of the same name, and the raw recording deleted when saving it failed — those
// last two lose a call — and the wrong Calendar event picked for it. ffmpeg is
// a stub on PATH that logs its arguments.
import { afterAll, beforeEach, expect, test } from "bun:test";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mode, save, which } from "@bin/obs/record";

const t = mkdtempSync(join(tmpdir(), "record-"));
const raw = join(t, "2026-10-20_12-16-26.mkv");
const log = join(t, "ffmpeg.log");
mkdirSync(join(t, "bin"));
writeFileSync(join(t, "bin", "ffmpeg"), `#!/bin/sh
echo "$*" >>"${log}"
[ -z "$FFMPEG_FAIL" ] || exit 1
for a; do last=$a; done; touch "$last"
`);
chmodSync(join(t, "bin", "ffmpeg"), 0o755);
process.env.PATH = `${join(t, "bin")}:${process.env.PATH}`;
const lastCall = () => readFileSync(log, "utf8").trim().split("\n").at(-1)!.replace(/.*-y /, "");

beforeEach(() => { writeFileSync(raw, ""); delete process.env.FFMPEG_FAIL; });
afterAll(() => rmSync(t, { recursive: true }));

test("Enter means audio", () => expect(mode("")).toBe("audio"));
test("v means video", () => expect(mode("v")).toBe("video"));
test("anything else is refused", () => expect(() => mode("x")).toThrow());

test("audio is saved as .m4a, named date-name, keeping every audio track and no video", async () => {
	expect(await save("audio", raw, `${t}/out`, "Porada s Šárkou!")).toBe(`${t}/out/20261020-porada-s-sarkou.m4a`);
	expect(lastCall()).toBe(`-i ${raw} -map 0:a -c copy ${t}/out/20261020-porada-s-sarkou.m4a`);
});

test("the raw file goes once it is saved", async () => {
	await save("audio", raw, `${t}/out`, "gone");
	expect(existsSync(raw)).toBe(false);
});

test("a second recording of the same name gets -2, never overwrites", async () => {
	await save("audio", raw, `${t}/out`, "twice");
	writeFileSync(raw, "");
	expect(await save("audio", raw, `${t}/out`, "Twice")).toBe(`${t}/out/20261020-twice-2.m4a`);
});

test("no name means date and time", async () =>
	expect(await save("audio", raw, `${t}/out`, "")).toBe(`${t}/out/20261020-12-16-26.m4a`));

test("video is saved as .mp4 and keeps everything", async () => {
	expect(await save("video", raw, `${t}/out`, "demo")).toBe(`${t}/out/20261020-demo.mp4`);
	expect(lastCall()).toBe(`-i ${raw} -map 0 -c copy ${t}/out/20261020-demo.mp4`);
});

test("a failed save fails and keeps the raw recording", async () => {
	process.env.FFMPEG_FAIL = "1";
	await expect(save("audio", raw, `${t}/out`, "x")).rejects.toThrow(raw);
	expect(existsSync(raw)).toBe(true);
});

test("Enter takes the best-fitting event, a number another, - none, anything else is asked again", () => {
	expect(which("", ["a", "b"])).toBe("a");
	expect(which("2", ["a", "b"])).toBe("b");
	expect(which("-", ["a", "b"])).toBeUndefined();
	expect(() => which("3", ["a", "b"])).toThrow();
	expect(() => which("x", ["a", "b"])).toThrow();
});
