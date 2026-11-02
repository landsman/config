#!/usr/bin/env bun
// Turns a call recording into text on this machine, with whisper.cpp. Each
// recording keeps the call and my mic on tracks of their own (see ../record/record.ts),
// so each is transcribed apart and the lines are merged by time: Me and Them
// need no guessing. Who is who inside Them comes from FluidAudio's offline
// diarizer (pyannote Community-1 on CoreML): Them 1, Them 2… by who spoke first,
// no names. It is told at most as many voices as the event has people;
// SPEAKERS=3 says exactly. Headphones on the call, or my mic hears Them too.
//
// Who was on the call goes into whisper's prompt, which is what spells their
// names right (../calendar/event.ts); the transcript opens with what the event and the
// diarizer say, as # lines. The models it runs on are in models.ts. SPOKEN=cs
// sets the language; auto-detect guesses it once per track from its first
// seconds. MODEL=quick|precise skips the question which model.
//
// usage: transcribe.ts setup        install whisper.cpp, download its models (4.7 GB, once)
//        transcribe.ts run [file]   the one given, or picked from ~/Recordings in television
//                                   (type 202610 for October): writes <recording>.txt beside it,
//                                   then offers to open Claude on it to file the call in the brain
import { $ } from "bun";
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, join } from "node:path";
import { callEvent, localDate, localTime } from "@bin/calls/calendar/event";
import type { CallEvent } from "@bin/calls/macos/calendar";
import {
	diarizer,
	diarizerModelsReady,
	setup,
	WhisperModel,
	whisperModelPath,
} from "@bin/calls/transcribe/models";
import { cli } from "@lib/cli";
import { ask, askUntil, done, gap, hint, link, live, o, pick, say, warn } from "@lib/term";

const recordingsFolder = process.env.RECORDINGS_DIR ?? `${homedir()}/Recordings`;

/** Quick or precise, as answered: Enter or q is quick, p is precise. */
export function chosenModel(answer = ""): WhisperModel {
	if (["", "q", "quick"].includes(answer)) {
		return WhisperModel.Quick;
	}
	if (["p", "precise"].includes(answer)) {
		return WhisperModel.Precise;
	}
	throw new Error(`quick or precise, not '${answer}'`);
}

/** Transcribes a recording into <recording>.txt and returns that path. */
export async function transcribe(recording: string): Promise<string> {
	if (!existsSync(recording)) {
		throw new Error(`no such recording: ${recording}`);
	}
	const model =
		process.env.MODEL || !process.stdin.isTTY
			? chosenModel(process.env.MODEL)
			: await askUntil(
					"Quick or precise?",
					"[Enter or q = quick, p = precise: better Czech, about 3× slower]",
					chosenModel,
				);
	const modelsMissing =
		!existsSync(whisperModelPath(model)) ||
		!existsSync(whisperModelPath(WhisperModel.SilenceDetector));
	if (modelsMissing) {
		await setup();
	}

	const { event, names } = await callEvent(recording);
	// My own name too, so whisper spells it; it is no voice on the call track.
	const namesToSpell = [...(event?.me ? [event.me] : []), ...names];

	const workFolder = mkdtempSync(join(tmpdir(), "transcribe-"));
	try {
		const heard: Track[] = [];
		let turns: Turn[] | null | undefined;
		for (const { who, track } of await tracksOf(recording)) {
			const audio = await extractTrack(recording, track, workFolder);
			const segments = await runWhisper(audio, model, namesToSpell, who || "the recording");
			if (who === "Them") {
				turns = await whoSpeaksWhen(audio, names.length);
				heard.push(...splitByVoice(who, segments, turns ?? []));
			} else {
				heard.push({ who, segments });
			}
		}

		const lines = transcriptLines(heard);
		if (!lines) {
			throw new Error(
				`no speech in ${basename(recording)}, nothing written: a muted mic, or the wrong input recorded?`,
			);
		}
		const transcript = transcriptHeader(event, names, turns, heard) + lines;
		const transcriptFile = freeTranscriptPath(recording);
		await Bun.write(transcriptFile, transcript);
		return transcriptFile;
	} finally {
		rmSync(workFolder, { recursive: true });
	}
}

/** OBS tracks 1 = both mixed, 2 = the call, 3 = me, so audio streams 0, 1, 2.
 *  A recording made otherwise is one voice. */
async function tracksOf(recording: string): Promise<{ who: string; track: number }[]> {
	const streams =
		await $`ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 ${recording}`.text();
	const audioStreams = streams.trim().split("\n").length;
	if (audioStreams >= 3) {
		return [
			{ who: "Them", track: 1 },
			{ who: "Me", track: 2 },
		];
	}
	return [{ who: "", track: 0 }];
}

/** One track as whisper reads it: 16 kHz mono WAV. */
async function extractTrack(recording: string, track: number, workFolder: string): Promise<string> {
	const audio = `${workFolder}/${track}.wav`;
	await $`ffmpeg -nostdin -loglevel error -i ${recording} -map 0:a:${track} -ar 16000 -ac 1 -c:a pcm_s16le ${audio}`;
	return audio;
}

async function runWhisper(
	audio: string,
	model: WhisperModel,
	namesToSpell: string[],
	whose: string,
): Promise<Segment[]> {
	const title = `Transcribing ${whose}`;
	live(title);
	const output = audio.replace(/\.wav$/, "");
	const prompt = namesToSpell.length ? ["--prompt", `${namesToSpell.join(", ")}.`] : [];
	const whisper = Bun.spawn(
		[
			"whisper-cli",
			"-m",
			whisperModelPath(model),
			"--vad",
			"-vm",
			whisperModelPath(WhisperModel.SilenceDetector),
			"-l",
			process.env.SPOKEN || "auto",
			...prompt,
			"-np",
			"-pp",
			"-oj",
			"-of",
			output,
			"-f",
			audio,
		],
		{ stdout: "ignore", stderr: "pipe" },
	);

	// -pp prints "progress = 40%" on stderr; it redraws the line above.
	let lastOutput = "";
	for await (const chunk of whisper.stderr.pipeThrough(new TextDecoderStream())) {
		lastOutput = (lastOutput + chunk).slice(-2000);
		const percent = [...chunk.matchAll(/progress = +(\d+)%/g)].at(-1)?.[1];
		if (percent && process.stdout.isTTY) {
			process.stdout.write(
				`\x1b[1A\r\x1b[K  ${o.red("●")} ${o.bold(title)}  ${o.dim(`${percent}%`)}\n`,
			);
		}
	}
	if ((await whisper.exited) !== 0) {
		throw new Error(`whisper failed:\n${lastOutput.trim()}`);
	}

	const result = JSON.parse(readFileSync(`${output}.json`, "utf8")) as {
		transcription: { offsets: { from: number; to: number }; text: string }[];
	};
	return result.transcription.map((piece) => {
		return { ...piece.offsets, text: piece.text };
	});
}

/** A stretch of speech whisper heard, in milliseconds from the start. */
export type Segment = { from: number; to: number; text: string };
/** A stretch where the diarizer heard one voice. */
export type Turn = { speaker: string; from: number; to: number };
type Track = { who: string; segments: Segment[] };

/** Splits one track by voice: each segment goes to the speaker it overlaps most,
 *  numbered by who spoke first. One voice, or none matched, stays just `who`. */
export function splitByVoice(who: string, segments: Segment[], turns: Turn[]): Track[] {
	const speakerOfSegment = segments.map((segment) => {
		let speaker = "";
		let longestOverlap = 0;
		for (const turn of turns) {
			const overlap = Math.min(segment.to, turn.to) - Math.max(segment.from, turn.from);
			if (overlap > longestOverlap) {
				speaker = turn.speaker;
				longestOverlap = overlap;
			}
		}
		return speaker;
	});

	const speakersInOrder = [...new Set(speakerOfSegment.filter(Boolean))];
	if (speakersInOrder.length < 2) {
		return [{ who, segments }];
	}
	const label = (speaker: string) =>
		speaker ? `${who} ${speakersInOrder.indexOf(speaker) + 1}` : who;
	const labels = [...new Set(speakerOfSegment.map(label))];
	return labels.map((voice) => {
		const theirs = segments.filter((_, index) => label(speakerOfSegment[index]) === voice);
		return { who: voice, segments: theirs };
	});
}

/** One line per turn: [mm:ss] Who: text, consecutive segments of one speaker joined up to a minute. */
export function transcriptLines(
	tracks: { who: string; segments: Pick<Segment, "from" | "text">[] }[],
): string {
	const spoken = tracks
		.flatMap(({ who, segments }) => {
			return segments.map((segment) => ({ who, from: segment.from, text: segment.text.trim() }));
		})
		// [BLANK_AUDIO], (music) and the like are whisper's notes, not speech.
		.filter((segment) => segment.text && !/^[[(].*[\])]$/.test(segment.text))
		.sort((first, second) => first.from - second.from);

	const lines: typeof spoken = [];
	for (const segment of spoken) {
		const previous = lines.at(-1);
		// A minute at most per line, or one voice talking is one line for the whole call.
		if (previous?.who === segment.who && segment.from - previous.from < 60_000) {
			previous.text += ` ${segment.text}`;
		} else {
			lines.push({ ...segment });
		}
	}
	return lines
		.map((line) => {
			const speaker = line.who ? `${line.who}: ` : "";
			return `[${callTime(line.from)}] ${speaker}${line.text}\n`;
		})
		.join("");
}

/** Milliseconds into the call as mm:ss, or h:mm:ss past an hour. */
function callTime(milliseconds: number): string {
	const seconds = Math.floor(milliseconds / 1000);
	const hours = Math.floor(seconds / 3600);
	const minutes = String(Math.floor(seconds / 60) % 60).padStart(2, "0");
	const minutesAndSeconds = `${minutes}:${String(seconds % 60).padStart(2, "0")}`;
	return hours ? `${hours}:${minutesAndSeconds}` : minutesAndSeconds;
}

/** What is known before the call is read, as # lines on top, for me and for the model
 *  that files it. Names stay off the lines: who is who is decided once the whole call is read. */
export function transcriptHeader(
	event: CallEvent | undefined,
	names: string[],
	turns: Turn[] | null | undefined,
	heard: Track[],
): string {
	const lines: string[] = [];
	if (event) {
		const when = `${localDate(event.start)} ${localTime(event.start)}–${localTime(event.end)}`;
		lines.push(`Event: ${event.title || "untitled"}, ${when}`);
	}
	if (names.length) {
		lines.push(`${event ? "Others on the event" : "On the event"}: ${names.join(", ")}`);
	}
	if (turns === null) {
		lines.push("Voices on the call track: not told apart, the diarizer did not run");
	} else if (turns) {
		const voices = new Set(turns.map((turn) => turn.speaker)).size;
		lines.push(`Voices on the call track: ${voices}, told apart by sound only`);
		const otherSide = heard.filter(
			(track) => track.who.startsWith("Them") && track.segments.length,
		);
		for (const { who, segments } of otherSide) {
			const spoke = segments.reduce((total, segment) => total + segment.to - segment.from, 0);
			const firstWords = Math.min(...segments.map((segment) => segment.from));
			lines.push(`  ${who.padEnd(7)} spoke ${callTime(spoke)}  first at ${callTime(firstWords)}`);
		}
		if (voices > 1) {
			lines.push("The lines say Them 1, Them 2…: who is who is not decided yet.");
		}
	}
	if (!lines.length) {
		return "";
	}
	return `${lines.map((line) => `# ${line}`).join("\n")}\n\n`;
}

/** <recording>.txt, or -2.txt, -3.txt…: never over an earlier one, it may have been corrected by hand. */
function freeTranscriptPath(recording: string): string {
	const withoutExtension = recording.replace(/\.[^./]*$/, "");
	let transcript = `${withoutExtension}.txt`;
	for (let copy = 2; existsSync(transcript); copy++) {
		transcript = `${withoutExtension}-${copy}.txt`;
	}
	return transcript;
}

/** Who speaks when on one track, in ms; null when the diarizer is not set up or fails,
 *  and the track then stays one voice rather than costing the transcript. */
async function whoSpeaksWhen(audio: string, peopleOnEvent: number): Promise<Turn[] | null> {
	if (!existsSync(diarizer.program) || !(await diarizerModelsReady())) {
		warn("FluidAudio is not set up (make record-init), Them stays one voice");
		return null;
	}
	live("Telling the voices apart");
	const howMany = process.env.SPEAKERS
		? ["--num-speakers", process.env.SPEAKERS]
		: peopleOnEvent
			? ["--max-speakers", String(peopleOnEvent)]
			: [];
	const output = `${audio}.voices.json`;
	const diarized =
		await $`${diarizer.program} process ${audio} --mode offline ${howMany} --output ${output}`
			.quiet()
			.nothrow();
	if (diarized.exitCode !== 0) {
		warn(
			`diarization failed, Them stays one voice:\n${diarized.stderr.toString().trim().slice(-500)}`,
		);
		return null;
	}
	const { segments } = JSON.parse(readFileSync(output, "utf8")) as {
		segments: { speakerId: string; startTimeSeconds: number; endTimeSeconds: number }[];
	};
	return segments.map((segment) => {
		return {
			speaker: segment.speakerId,
			from: segment.startTimeSeconds * 1000,
			to: segment.endTimeSeconds * 1000,
		};
	});
}

async function run(recording?: string) {
	gap();
	// A script reading the path gets the newest without a question.
	recording ??= process.stdin.isTTY ? await pickRecording() : allRecordings()[0];
	const transcript = await transcribe(recording);
	if (!process.stdout.isTTY) {
		return say(transcript);
	}
	gap();
	done(`Transcribed ${basename(transcript)}`);
	say(`  ${link(transcript)}`);
	hint("⌘ + click to open");
	gap();
	await fileInBrain(transcript);
}

/** The recordings in ~/Recordings, one per call's folder, the last one saved first.
 *  A loose one is found too, until record-init has given it a folder. */
export function allRecordings(folder = recordingsFolder): string[] {
	const recordingsIn = (inFolder: string) => {
		return readdirSync(inFolder)
			.filter((file) => /\.(m4a|mp4)$/.test(file))
			.map((file) => join(inFolder, file));
	};
	const callFolders = readdirSync(folder)
		.filter((name) => !name.startsWith(".") && statSync(join(folder, name)).isDirectory())
		.map((name) => join(folder, name));
	const recordings = [recordingsIn(folder), ...callFolders.map(recordingsIn)]
		.flat()
		.sort((first, second) => statSync(second).mtimeMs - statSync(first).mtimeMs);
	if (!recordings.length) {
		throw new Error(`no recording in ${folder}`);
	}
	return recordings;
}

/** Picks a recording in television, newest first, by the call's name. That opens with
 *  its date, so typing 2026, 202610 or 20261020 filters by year, month or day. */
async function pickRecording(): Promise<string> {
	if (!Bun.which("tv")) {
		throw new Error("television is missing: brew install television, or give FILE=…");
	}
	const recordingByName = new Map(
		allRecordings().map((recording) => [basename(recording), recording]),
	);
	const picked = await pick("Recording to transcribe", [...recordingByName.keys()]);
	if (!picked) {
		throw new Error("no recording picked");
	}
	return recordingByName.get(picked) ?? join(recordingsFolder, picked);
}

/** Opens Claude on a fresh transcript, to file the call in the brain and say what came of it. BRAIN=n skips the question. */
export async function fileInBrain(transcript: string) {
	if (!process.stdin.isTTY) {
		return;
	}
	if (!Bun.which("claude")) {
		return warn("claude is missing, the transcript stays out of the brain");
	}
	const answer =
		process.env.BRAIN ?? (await ask("File it in the brain with Claude?", "[Enter = yes, n = no]"));
	if (["n", "no"].includes(answer.toLowerCase())) {
		return;
	}
	// Interactive, not claude -p: its writes to the brain need approving, and its questions an answer.
	const claude = Bun.spawn(["claude", brainPrompt(transcript)], {
		cwd: `${homedir()}/projects/landsman/brain`,
		stdio: ["inherit", "inherit", "inherit"],
	});
	await claude.exited;
}

export function brainPrompt(transcript: string): string {
	return [
		`Here is a machine transcript of my call: ${transcript}. "Me" is me, "Them" is the other side;`,
		"Them 1, Them 2… are its voices told apart by sound, numbered by who spoke first, without names:",
		"a name for one is a guess from what is said, and is marked as one.",
		"The # lines on top say what was known before the call was read: the event, who was on it, the voices heard.",
		"It mis-hears names, products and numbers, so take it as the gist and mark what you had to guess.",
		"Who the call was with and what it is about is in the file name and in the brain; if neither says, ask me.",
		"File it in the brain: the transcript verbatim as the raw source, and in the wiki what we talked about,",
		"what we agreed on and who does what. Then give me the same here, in Czech.",
	].join(" ");
}

if (import.meta.main) {
	await cli(import.meta.path, { setup, run });
}
