// What transcribe.ts would get wrong silently: the two tracks merged out of
// order, a turn split on every segment or never, whisper's own notes read as speech,
// and Enter not meaning the quick model; a voice from the diarizer put on the wrong lines; and
// a header that miscounts the voices or names one before the call was read.
// And a network that blocks Hugging Face, which curl reports only as a 403.
import { expect, test } from "bun:test";
import { checkHuggingFaceAllows, WhisperModel } from "@bin/calls/transcribe/models";
import {
	chosenModel,
	splitByVoice,
	transcriptHeader,
	transcriptLines,
} from "@bin/calls/transcribe/transcribe";

test("tracks are merged by time, one line per turn", () =>
	expect(
		transcriptLines([
			{
				who: "Them",
				segments: [
					{ from: 0, text: " Ahoj." },
					{ from: 2000, text: " Slyšíš mě?" },
					{ from: 9000, text: " Super." },
				],
			},
			{
				who: "Me",
				segments: [
					{ from: 5000, text: " Jo, slyším." },
					{ from: 3_725_000, text: " Čau." },
				],
			},
		]),
	).toBe(
		"[00:00] Them: Ahoj. Slyšíš mě?\n[00:05] Me: Jo, slyším.\n[00:09] Them: Super.\n[1:02:05] Me: Čau.\n",
	));

test("whisper's notes and empty segments are dropped", () =>
	expect(
		transcriptLines([
			{
				who: "Me",
				segments: [
					{ from: 0, text: " [BLANK_AUDIO]" },
					{ from: 1, text: " (hudba)" },
					{ from: 2, text: " " },
				],
			},
		]),
	).toBe(""));

test("a long turn starts a new line every minute", () =>
	expect(
		transcriptLines([
			{
				who: "Them",
				segments: [
					{ from: 0, text: "A." },
					{ from: 59_000, text: "B." },
					{ from: 60_000, text: "C." },
				],
			},
		]),
	).toBe("[00:00] Them: A. B.\n[01:00] Them: C.\n"));

test("one unlabelled track has no speaker", () =>
	expect(transcriptLines([{ who: "", segments: [{ from: 61_000, text: "Hello." }] }])).toBe(
		"[01:01] Hello.\n",
	));

test("a track is split by the voice each segment overlaps most, numbered by who spoke first", () => {
	const turns = [
		{ speaker: "S7", from: 0, to: 4000 },
		{ speaker: "S2", from: 4000, to: 9000 },
		{ speaker: "S7", from: 9000, to: 12_000 },
	];
	const segments = [
		{ from: 0, to: 3000, text: "A" },
		{ from: 3000, to: 8000, text: "B" },
		{ from: 9500, to: 11_000, text: "C" },
		{ from: 20_000, to: 21_000, text: "D" },
	];
	expect(splitByVoice("Them", segments, turns)).toEqual([
		{ who: "Them 1", segments: [segments[0], segments[2]] },
		{ who: "Them 2", segments: [segments[1]] },
		{ who: "Them", segments: [segments[3]] },
	]);
});

test("one voice, or no diarization at all, keeps the track as it was", () => {
	const segments = [{ from: 0, to: 1000, text: "A" }];
	expect(splitByVoice("Them", segments, [{ speaker: "S1", from: 0, to: 5000 }])).toEqual([
		{ who: "Them", segments },
	]);
	expect(splitByVoice("Them", segments, [])).toEqual([{ who: "Them", segments }]);
});

test("the header says the event, who was on it and each voice, and names none of them", () => {
	const event = {
		uuid: "U",
		title: "Sync",
		start: new Date(2026, 9, 21, 14).toISOString(),
		end: new Date(2026, 9, 21, 14, 30).toISOString(),
		me: "Me",
		people: ["Jana", "Petr"],
	};
	const turns = [
		{ speaker: "S1", from: 0, to: 9000 },
		{ speaker: "S2", from: 9000, to: 20_000 },
	];
	const heard = [
		{
			who: "Them 1",
			segments: [
				{ from: 3000, to: 5000, text: "A" },
				{ from: 6000, to: 7000, text: "B" },
			],
		},
		{ who: "Them 2", segments: [{ from: 41_000, to: 47_000, text: "C" }] },
		{ who: "Me", segments: [{ from: 0, to: 1000, text: "D" }] },
	];
	expect(transcriptHeader(event, ["Jana", "Petr"], turns, heard)).toBe(
		[
			"# Event: Sync, 2026-10-21 14:00–14:30",
			"# Others on the event: Jana, Petr",
			"# Voices on the call track: 2, told apart by sound only",
			"#   Them 1  spoke 00:03  first at 00:03",
			"#   Them 2  spoke 00:06  first at 00:41",
			"# The lines say Them 1, Them 2…: who is who is not decided yet.",
			"",
			"",
		].join("\n"),
	);
});

test("without an event or a diarizer the header says so, and without either it is gone", () => {
	expect(transcriptHeader(undefined, [], null, [])).toBe(
		"# Voices on the call track: not told apart, the diarizer did not run\n\n",
	);
	expect(transcriptHeader(undefined, [], undefined, [{ who: "", segments: [] }])).toBe("");
});

test("Enter means quick, p precise, anything else is refused", () => {
	expect(chosenModel("")).toBe(WhisperModel.Quick);
	expect(chosenModel("p")).toBe(WhisperModel.Precise);
	expect(() => chosenModel("x")).toThrow();
});

test("a network that blocks Hugging Face stops setup with what to do, not a bare 403", async () => {
	const webFilter = Bun.serve({ port: 0, fetch: () => new Response(null, { status: 403 }) });
	try {
		await expect(checkHuggingFaceAllows(webFilter.url.href, "/models")).rejects.toThrow(
			/answered 403[\s\S]*copy them into \/models/,
		);
	} finally {
		webFilter.stop();
	}
});

test("a reachable Hugging Face lets setup download", async () => {
	const huggingFace = Bun.serve({ port: 0, fetch: () => new Response(null) });
	try {
		await checkHuggingFaceAllows(huggingFace.url.href, "/models");
	} finally {
		huggingFace.stop();
	}
});

test("an unreachable Hugging Face stops setup with the same advice", async () => {
	const closedPort = Bun.serve({ port: 0, fetch: () => new Response(null) });
	const url = closedPort.url.href;
	closedPort.stop(true);
	await expect(checkHuggingFaceAllows(url, "/models")).rejects.toThrow(
		/could not be reached[\s\S]*copy them into \/models/,
	);
});
