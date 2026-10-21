#!/usr/bin/env bun
// Turns a call recording into text on this machine, with whisper.cpp. Each
// recording keeps the call and my mic on tracks of their own (see record.ts),
// so each is transcribed apart and the lines are merged by time: Me and Them
// need no guessing. Who is who inside Them does not come out of this, it would
// take a diarization model. Headphones on the call, or my mic hears Them too.
//
// The participants of a calendar event go into whisper's prompt, which is what
// spells their names right: an .ics file or an event dragged out of Calendar,
// see calendar.ts. SPOKEN=cs sets the language; auto-detect
// guesses it once per track from its first seconds. MODEL=quick|precise skips
// the question which model.
//
// usage: transcribe.ts setup        install whisper.cpp, download its models (4.7 GB, once)
//        transcribe.ts run [file]   the one given, or picked from ~/Recordings in television
//                                   (type 202610 for October): writes <recording>.txt beside it,
//                                   then offers to open Claude on it to file the call in the brain
import { $ } from "bun";
import { existsSync, mkdtempSync, readdirSync, readFileSync, renameSync, rmSync, statSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, join } from "node:path";
import { participants } from "@bin/obs/calendar";
import { cli } from "@lib/cli";
import { ask, done, gap, hint, link, live, o, say, warn } from "@lib/term";

const out = process.env.RECORDINGS_DIR ?? `${homedir()}/Recordings`;
const models = `${homedir()}/.cache/whisper`;
// Pinned by checksum: a model is code whisper runs over every call.
const files = {
	// Turbo is large-v3 with 4 decoder layers instead of 32: several times
	// faster, and it loses the most on languages other than English.
	quick: {
		name: "ggml-large-v3-turbo.bin",
		url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin",
		sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
	},
	precise: {
		name: "ggml-large-v3.bin",
		url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin",
		sha256: "64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2",
	},
	// Silence goes to whisper as nothing at all; fed to it, it makes up
	// sentences ("Titulky vytvořil…"), and a muted mic is mostly silence.
	vad: {
		name: "ggml-silero-v6.2.0.bin",
		url: "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v6.2.0.bin",
		sha256: "2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987",
	},
};
const model = (m: keyof typeof files) => `${models}/${files[m].name}`;

export type Speed = "quick" | "precise";

export function speed(answer = ""): Speed {
	if (["", "q", "quick"].includes(answer)) return "quick";
	if (["p", "precise"].includes(answer)) return "precise";
	throw new Error(`quick or precise, not '${answer}'`);
}

export type Segment = { from: number; text: string };

/** One line per turn: [mm:ss] Who: text, consecutive segments of one speaker joined up to a minute. */
export function merge(tracks: { who: string; segments: Segment[] }[]): string {
	const all = tracks
		.flatMap(({ who, segments }) => segments.map((s) => ({ who, ...s, text: s.text.trim() })))
		// [BLANK_AUDIO], (music) and the like are whisper's notes, not speech.
		.filter((s) => s.text && !/^[[(].*[\])]$/.test(s.text))
		.sort((a, b) => a.from - b.from);
	const turns: typeof all = [];
	for (const s of all) {
		const last = turns.at(-1);
		// A minute at most per line, or one voice talking is one line for the whole call.
		if (last?.who === s.who && s.from - last.from < 60_000) last.text += ` ${s.text}`;
		else turns.push({ ...s });
	}
	return turns.map((t) => `[${clock(t.from)}] ${t.who ? `${t.who}: ` : ""}${t.text}\n`).join("");
}

const clock = (ms: number) => {
	const s = Math.floor(ms / 1000), h = Math.floor(s / 3600);
	const mmss = `${String(Math.floor(s / 60) % 60).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
	return h ? `${h}:${mmss}` : mmss;
};

/** A path dragged into a terminal arrives quoted or with escaped spaces; a typed one may start with ~. */
export const dropped = (s: string) =>
	s.trim().replace(/^'(.*)'$/, "$1").replace(/^"(.*)"$/, "$1").replace(/\\(.)/g, "$1").replace(/^~(?=\/)/, homedir());

async function sha256(path: string) {
	const h = new Bun.CryptoHasher("sha256");
	for await (const chunk of Bun.file(path).stream()) h.update(chunk);
	return h.digest("hex");
}

async function setup() {
	if (!Bun.which("whisper-cli")) await $`brew install whisper.cpp`;
	for (const m of ["quick", "precise", "vad"] as const) {
		const { url, sha256: sum } = files[m], dst = model(m);
		if (existsSync(dst)) continue;
		live(`Downloading ${files[m].name}`);
		await $`mkdir -p ${models} && curl -fL --progress-bar -o ${dst}.part ${url}`;
		if ((await sha256(`${dst}.part`)) !== sum) {
			rmSync(`${dst}.part`);
			throw new Error(`${files[m].name} does not match its checksum, deleted`);
		}
		renameSync(`${dst}.part`, dst);
	}
	done("whisper.cpp is set up", models);
}

/** The recordings in ~/Recordings, the last one saved first. */
function recordings(): string[] {
	const all = readdirSync(out)
		.filter((f) => /\.(m4a|mp4)$/.test(f))
		.map((f) => join(out, f))
		.sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);
	if (!all.length) throw new Error(`no recording in ${out}`);
	return all;
}

/** Picks a recording in television, newest first. A name opens with its date,
 *  so typing 2026, 202610 or 20261020 filters by year, month or day. */
async function choose(): Promise<string> {
	if (!Bun.which("tv")) throw new Error("television is missing: brew install television, or give FILE=…");
	const list = recordings().map((f) => basename(f)).join("\n");
	const tv = Bun.spawn(["tv", "--no-preview", "--input-header", "Recording to transcribe"], { stdin: new Blob([list]), stdout: "pipe", stderr: "inherit" });
	const picked = (await new Response(tv.stdout).text()).trim();
	if (!picked) throw new Error("no recording picked");
	return join(out, picked);
}

/** Transcribes a recording into <recording>.txt and returns that path. */
export async function transcribe(file: string): Promise<string> {
	if (!existsSync(file)) throw new Error(`no such recording: ${file}`);
	const s = speed(process.env.MODEL ?? (process.stdin.isTTY ? await ask("Quick or precise?", "[Enter = quick, p = precise: better Czech, about 3× slower]") : ""));
	if (!existsSync(model(s)) || !existsSync(model("vad"))) await setup();
	let event = dropped(process.env.ICS ?? "");
	if (!event && process.stdin.isTTY) event = dropped(await ask("Calendar event, drag it here from Calendar or as .ics", "[Enter = none]"));
	const names = participants(event);
	if (names.length) hint(`Names: ${names.join(", ")}`);

	// OBS tracks 1 = both mixed, 2 = the call, 3 = me, so audio streams 0, 1, 2.
	// A recording made otherwise is one voice.
	const count = (await $`ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 ${file}`.text()).trim().split("\n").length;
	const tracks = count >= 3 ? [{ who: "Them", track: 1 }, { who: "Me", track: 2 }] : [{ who: "", track: 0 }];
	const tmp = mkdtempSync(join(tmpdir(), "transcribe-"));
	try {
		const heard = [];
		for (const { who, track } of tracks) {
			const what = `Transcribing ${who || "the recording"}`;
			live(what);
			const wav = `${tmp}/${track}.wav`;
			await $`ffmpeg -nostdin -loglevel error -i ${file} -map 0:a:${track} -ar 16000 -ac 1 -c:a pcm_s16le ${wav}`;
			const prompt = names.length ? ["--prompt", `${names.join(", ")}.`] : [];
			const whisper = Bun.spawn(["whisper-cli", "-m", model(s), "--vad", "-vm", model("vad"), "-l", process.env.SPOKEN || "auto",
				...prompt, "-np", "-pp", "-oj", "-of", `${tmp}/${track}`, "-f", wav], { stdout: "ignore", stderr: "pipe" });
			// -pp prints "progress = 40%" on stderr; it redraws the line above.
			let log = "";
			for await (const chunk of whisper.stderr.pipeThrough(new TextDecoderStream())) {
				log = (log + chunk).slice(-2000);
				const p = [...chunk.matchAll(/progress = +(\d+)%/g)].at(-1)?.[1];
				if (p && process.stdout.isTTY) process.stdout.write(`\x1b[1A\r\x1b[K  ${o.red("●")} ${o.bold(what)}  ${o.dim(`${p}%`)}\n`);
			}
			if ((await whisper.exited) !== 0) throw new Error(`whisper failed:\n${log.trim()}`);
			const json = JSON.parse(readFileSync(`${tmp}/${track}.json`, "utf8"));
			heard.push({ who, segments: (json.transcription as { offsets: { from: number }; text: string }[]).map((s) => ({ from: s.offsets.from, text: s.text })) });
		}
		const text = merge(heard);
		if (!text) throw new Error(`no speech in ${basename(file)}, nothing written: a muted mic, or the wrong input recorded?`);
		// Never over an earlier one: it may have been corrected by hand.
		let txt = file.replace(/\.[^.]*$/, ".txt");
		for (let i = 2; existsSync(txt); i++) txt = file.replace(/\.[^.]*$/, `-${i}.txt`);
		await Bun.write(txt, text);
		return txt;
	} finally {
		rmSync(tmp, { recursive: true });
	}
}

async function run(file?: string) {
	gap();
	// A script reading the path gets the newest without a question.
	file ??= process.stdin.isTTY ? await choose() : recordings()[0];
	const txt = await transcribe(file);
	if (!process.stdout.isTTY) return say(txt);
	gap();
	done(`Transcribed ${txt.split("/").at(-1)}`);
	say(`  ${link(txt)}`);
	hint("⌘ + click to open");
	gap();
	await toBrain(txt);
}

/** Opens Claude on a fresh transcript, to file the call in the brain and say what came of it. BRAIN=n skips the question. */
export async function toBrain(txt: string) {
	if (!process.stdin.isTTY) return;
	if (!Bun.which("claude")) return warn("claude is missing, the transcript stays out of the brain");
	const answer = process.env.BRAIN ?? (await ask("File it in the brain with Claude?", "[Enter = yes, n = no]"));
	if (["n", "no"].includes(answer.toLowerCase())) return;
	// Interactive, not claude -p: its writes to the brain need approving, and its questions an answer.
	await Bun.spawn(["claude", handover(txt)], { cwd: `${homedir()}/projects/landsman/brain`, stdio: ["inherit", "inherit", "inherit"] }).exited;
}

export const handover = (txt: string) =>
	`Here is a machine transcript of my call: ${txt}. "Me" is me, "Them" is the other side. ` +
	"It mis-hears names, products and numbers, so take it as the gist and mark what you had to guess. " +
	"Who the call was with and what it is about is in the file name and in the brain; if neither says, ask me. " +
	"File it in the brain: the transcript verbatim as the raw source, and in the wiki what we talked about, " +
	"what we agreed on and who does what. Then give me the same here, in Czech.";

if (import.meta.main) await cli(import.meta.path, { setup, run });
