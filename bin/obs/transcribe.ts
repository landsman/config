#!/usr/bin/env bun
// Turns a call recording into text on this machine, with whisper.cpp. Each
// recording keeps the call and my mic on tracks of their own (see record.ts),
// so each is transcribed apart and the lines are merged by time: Me and Them
// need no guessing. Who is who inside Them comes from FluidAudio's offline
// diarizer (pyannote Community-1 on CoreML): Them 1, Them 2… by who spoke first,
// no names. It is told at most as many voices as the event has people;
// SPEAKERS=3 says exactly. Headphones on the call, or my mic hears Them too.
//
// The participants of a calendar event go into whisper's prompt, which is what
// spells their names right: the event record.ts found in Calendar when the call
// stopped (<recording>.event.json), else an .ics file or an event dragged out of
// Apple Calendar (apple-calendar.ts). The transcript opens with what that event
// and the diarizer say, as # lines. One known only by address is named in
// contacts.ts. SPOKEN=cs sets the language; auto-detect
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
import { basename, dirname, join } from "node:path";
import { appleCalendarAttendees, appleEventId, type CallEvent } from "@bin/obs/apple-calendar";
import { realNames } from "@bin/obs/contacts";
import { cli } from "@lib/cli";
import { ask, askUntil, done, gap, hint, link, live, o, say, warn } from "@lib/term";

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

// The diarizer is built from a pinned commit, and that commit pins its models'
// revision; the models are checked against one hash over all their files
// before the CLI ever loads them. No release ships a binary.
const fluid = {
	tag: "v0.17.7",
	commit: "503b4bd1bbf7220882de39fe8ae6716aae4132da",
	bin: `${homedir()}/.cache/fluidaudio/fluidaudiocli-0.17.7`,
	repo: "FluidInference/speaker-diarization-coreml",
	revision: "df2625ac79a7ac6b65ad868fee6d80f320da4232",
	// shasum -a 256 of every file, sorted by path, hashed again
	tree: "ff077a5564c55aa1063dfb4ae11d472f80190f380ae9602686f5ce8420863c12",
	dir: `${homedir()}/Library/Application Support/FluidAudio/Models/speaker-diarization-coreml`,
	files: /^(Segmentation|FBank|Embedding|PldaRho)\.mlmodelc\/|^plda-parameters\.json$/,
};

export type Speed = "quick" | "precise";

export function speed(answer = ""): Speed {
	if (["", "q", "quick"].includes(answer)) return "quick";
	if (["p", "precise"].includes(answer)) return "precise";
	throw new Error(`quick or precise, not '${answer}'`);
}

export type Segment = { from: number; to: number; text: string };
export type Turn = { speaker: string; from: number; to: number };

/** Splits one track by voice: each segment goes to the speaker it overlaps most,
 *  numbered by who spoke first. One voice, or none matched, stays just `who`. */
export function diarize(who: string, segments: Segment[], turns: Turn[]): { who: string; segments: Segment[] }[] {
	const voice = segments.map((s) => {
		let best = "", most = 0;
		for (const t of turns) {
			const overlap = Math.min(s.to, t.to) - Math.max(s.from, t.from);
			if (overlap > most) [best, most] = [t.speaker, overlap];
		}
		return best;
	});
	const order = [...new Set(voice.filter(Boolean))];
	if (order.length < 2) return [{ who, segments }];
	const label = (v: string) => (v ? `${who} ${order.indexOf(v) + 1}` : who);
	return [...new Set(voice.map(label))].map((l) => ({ who: l, segments: segments.filter((_, i) => label(voice[i]) === l) }));
}

/** One line per turn: [mm:ss] Who: text, consecutive segments of one speaker joined up to a minute. */
export function merge(tracks: { who: string; segments: Pick<Segment, "from" | "text">[] }[]): string {
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

/** The people on a calendar event, its organizer and attendees: a name, or an address when it has none. */
export function attendees(ics: string): string[] {
	const unfolded = ics.replace(/\r?\n[ \t]/g, ""); // a long line goes on after a newline and a space
	return [...new Set([...unfolded.matchAll(/^(?:ATTENDEE|ORGANIZER)[^:\n]*?;CN=("?)([^";:\n]+)\1/gm)].map((m) => m[2].trim()))];
}

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
	if (!Bun.which("swift")) return warn("swift is missing (install Xcode): transcripts keep one Them, unsplit by voice");
	if (!existsSync(fluid.bin)) await buildFluid();
	if (!(await fluidReady())) await fetchFluidModels();
	done("FluidAudio is set up", fluid.bin);
}

async function buildFluid() {
	live(`Building FluidAudio ${fluid.tag}, once`);
	const src = mkdtempSync(join(tmpdir(), "fluidaudio-"));
	try {
		await $`git -c advice.detachedHead=false clone -q --depth 1 --branch ${fluid.tag} https://github.com/FluidInference/FluidAudio.git ${src}`;
		const head = (await $`git -C ${src} rev-parse HEAD`.text()).trim();
		if (head !== fluid.commit) throw new Error(`FluidAudio ${fluid.tag} is ${head} now, not ${fluid.commit}: the tag moved`);
		await $`swift build -c release --product fluidaudiocli --package-path ${src}`.quiet();
		await $`mkdir -p ${dirname(fluid.bin)} && cp ${src}/.build/release/fluidaudiocli ${fluid.bin}`;
	} finally {
		rmSync(src, { recursive: true });
	}
}

/** Whether the models on disk are exactly the pinned ones, and marked as that revision for the CLI. */
async function fluidReady(dir = fluid.dir) {
	if (!existsSync(`${dir}/.fluidaudio-revision`)) return false;
	return (await treeHash(dir)) === fluid.tree;
}

async function treeHash(dir: string) {
	const paths = readdirSync(dir, { recursive: true, encoding: "utf8" })
		.filter((p) => fluid.files.test(p) && statSync(join(dir, p)).isFile())
		.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
	let lines = "";
	for (const p of paths) lines += `${await sha256(join(dir, p))}  ${p}\n`;
	return new Bun.CryptoHasher("sha256").update(lines).digest("hex");
}

async function fetchFluidModels() {
	live("Downloading the diarization models (22 MB)");
	const api = `https://huggingface.co/api/models/${fluid.repo}/revision/${fluid.revision}`;
	const names = ((await (await fetch(api)).json()) as { siblings: { rfilename: string }[] }).siblings
		.map((s) => s.rfilename).filter((f) => fluid.files.test(f));
	const part = `${fluid.dir}.part`;
	rmSync(part, { recursive: true, force: true });
	for (const f of names) await $`mkdir -p ${dirname(`${part}/${f}`)} && curl -fsSL -o ${`${part}/${f}`} ${`https://huggingface.co/${fluid.repo}/resolve/${fluid.revision}/${f}`}`;
	if ((await treeHash(part)) !== fluid.tree) {
		rmSync(part, { recursive: true });
		throw new Error("the diarization models do not match their checksum, deleted");
	}
	// The CLI takes a folder marked with its own pinned revision as downloaded.
	await Bun.write(`${part}/.fluidaudio-revision`, fluid.revision);
	rmSync(fluid.dir, { recursive: true, force: true });
	renameSync(part, fluid.dir);
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
	const s = process.env.MODEL || !process.stdin.isTTY ? speed(process.env.MODEL) : await askUntil("Quick or precise?", "[Enter or q = quick, p = precise: better Czech, about 3× slower]", speed);
	if (!existsSync(model(s)) || !existsSync(model("vad"))) await setup();
	// The event saved when the call was stopped; asked for only when there is none.
	const event = existsSync(eventFile(file)) ? (JSON.parse(readFileSync(eventFile(file), "utf8")) as CallEvent) : undefined;
	let ics = event ? "" : dropped(process.env.ICS ?? "");
	if (!event && !ics && process.stdin.isTTY) ics = dropped(await ask("Calendar event, drag it here from Calendar or as .ics", "[Enter = none]"));
	// A mistyped path costs the names, not the transcript.
	const apple = appleEventId(ics);
	const people = event?.people ?? (apple ? appleCalendarAttendees(apple) : ics && existsSync(ics) ? attendees(readFileSync(ics, "utf8")) : []);
	if (apple && !people.length) warn("no such event in Calendar, going on without names");
	else if (ics && !apple && !existsSync(ics)) warn(`no such file, going on without names: ${ics}`);
	const names = await realNames(people);
	if (event) hint(`Event: ${event.title}`);
	if (names.length) hint(`Names: ${names.join(", ")}`);
	// My own name too, so whisper spells it; it is no voice on the call track.
	const spelled = [...(event?.me ? [event.me] : []), ...names];

	// OBS tracks 1 = both mixed, 2 = the call, 3 = me, so audio streams 0, 1, 2.
	// A recording made otherwise is one voice.
	const count = (await $`ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 ${file}`.text()).trim().split("\n").length;
	const tracks = count >= 3 ? [{ who: "Them", track: 1 }, { who: "Me", track: 2 }] : [{ who: "", track: 0 }];
	const tmp = mkdtempSync(join(tmpdir(), "transcribe-"));
	try {
		const heard = [];
		let turns: Turn[] | null | undefined;
		for (const { who, track } of tracks) {
			const what = `Transcribing ${who || "the recording"}`;
			live(what);
			const wav = `${tmp}/${track}.wav`;
			await $`ffmpeg -nostdin -loglevel error -i ${file} -map 0:a:${track} -ar 16000 -ac 1 -c:a pcm_s16le ${wav}`;
			const prompt = spelled.length ? ["--prompt", `${spelled.join(", ")}.`] : [];
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
			const segments = (json.transcription as { offsets: { from: number; to: number }; text: string }[]).map((s) => ({ ...s.offsets, text: s.text }));
			if (who === "Them") turns = await voices(wav, names.length);
			heard.push(...(who === "Them" ? diarize(who, segments, turns ?? []) : [{ who, segments }]));
		}
		const lines = merge(heard);
		if (!lines) throw new Error(`no speech in ${basename(file)}, nothing written: a muted mic, or the wrong input recorded?`);
		const text = header(event, names, turns, heard) + lines;
		// Never over an earlier one: it may have been corrected by hand.
		let txt = file.replace(/\.[^.]*$/, ".txt");
		for (let i = 2; existsSync(txt); i++) txt = file.replace(/\.[^.]*$/, `-${i}.txt`);
		await Bun.write(txt, text);
		return txt;
	} finally {
		rmSync(tmp, { recursive: true });
	}
}

export const eventFile = (recording: string) => recording.replace(/\.[^.]*$/, ".event.json");

/** What is known before the call is read, as # lines on top, for me and for the model
 *  that files it. Names stay off the lines: who is who is decided once the whole call is read. */
export function header(event: CallEvent | undefined, names: string[], turns: Turn[] | null | undefined, heard: { who: string; segments: Segment[] }[]): string {
	const lines: string[] = [];
	if (event) lines.push(`Event: ${event.title || "untitled"}, ${day(event.start)} ${hm(event.start)}–${hm(event.end)}`);
	if (names.length) lines.push(`${event ? "Others on the event" : "On the event"}: ${names.join(", ")}`);
	if (turns === null) lines.push("Voices on the call track: not told apart, the diarizer did not run");
	else if (turns) {
		const count = new Set(turns.map((t) => t.speaker)).size;
		lines.push(`Voices on the call track: ${count}, told apart by sound only`);
		for (const { who, segments } of heard.filter((t) => t.who.startsWith("Them") && t.segments.length)) {
			const spoke = segments.reduce((sum, s) => sum + s.to - s.from, 0);
			lines.push(`  ${who.padEnd(7)} spoke ${clock(spoke)}  first at ${clock(Math.min(...segments.map((s) => s.from)))}`);
		}
		if (count > 1) lines.push("The lines say Them 1, Them 2…: who is who is not decided yet.");
	}
	return lines.length ? `${lines.map((l) => `# ${l}`).join("\n")}\n\n` : "";
}

const pad = (n: number) => String(n).padStart(2, "0");
const day = (iso: string) => { const d = new Date(iso); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; };
const hm = (iso: string) => { const d = new Date(iso); return `${pad(d.getHours())}:${pad(d.getMinutes())}`; };

/** Who speaks when on one track, in ms; null when the diarizer is not set up or fails,
 *  and the track then stays one voice rather than costing the transcript. */
async function voices(wav: string, people: number): Promise<Turn[] | null> {
	if (!existsSync(fluid.bin) || !(await fluidReady())) {
		warn("FluidAudio is not set up (make record-init), Them stays one voice");
		return null;
	}
	live("Telling the voices apart");
	const count = process.env.SPEAKERS ? ["--num-speakers", process.env.SPEAKERS] : people ? ["--max-speakers", String(people)] : [];
	const json = `${wav}.voices.json`;
	const run = await $`${fluid.bin} process ${wav} --mode offline ${count} --output ${json}`.quiet().nothrow();
	if (run.exitCode !== 0) {
		warn(`diarization failed, Them stays one voice:\n${run.stderr.toString().trim().slice(-500)}`);
		return null;
	}
	const { segments } = JSON.parse(readFileSync(json, "utf8")) as { segments: { speakerId: string; startTimeSeconds: number; endTimeSeconds: number }[] };
	return segments.map((s) => ({ speaker: s.speakerId, from: s.startTimeSeconds * 1000, to: s.endTimeSeconds * 1000 }));
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
	`Here is a machine transcript of my call: ${txt}. "Me" is me, "Them" is the other side; ` +
	"Them 1, Them 2… are its voices told apart by sound, numbered by who spoke first, without names: " +
	"a name for one is a guess from what is said, and is marked as one. " +
	"The # lines on top say what was known before the call was read: the event, who was on it, the voices heard. " +
	"It mis-hears names, products and numbers, so take it as the gist and mark what you had to guess. " +
	"Who the call was with and what it is about is in the file name and in the brain; if neither says, ask me. " +
	"File it in the brain: the transcript verbatim as the raw source, and in the wiki what we talked about, " +
	"what we agreed on and who does what. Then give me the same here, in Czech.";

if (import.meta.main) await cli(import.meta.path, { setup, run });
