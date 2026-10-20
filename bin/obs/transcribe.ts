#!/usr/bin/env bun
// Turns a call recording into text on this machine, with whisper.cpp. Each
// recording keeps the call and my mic on tracks of their own (see record.ts),
// so each is transcribed apart and the lines are merged by time: Me and Them
// need no guessing. Who is who inside Them does not come out of this, it would
// take a diarization model. Headphones on the call, or my mic hears Them too.
//
// The participants of a calendar event (.ics) go into whisper's prompt, which
// is what spells their names right. SPOKEN=cs sets the language; auto-detect
// guesses it once per track from its first seconds.
//
// usage: transcribe.ts setup        install whisper.cpp, download its models (1.6 GB, once)
//        transcribe.ts run [file]   the latest recording in ~/Recordings, or the one given:
//                                   writes <recording>.txt beside it, prints the path
import { $ } from "bun";
import { existsSync, mkdtempSync, readdirSync, readFileSync, renameSync, rmSync, statSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { cli } from "@lib/cli";
import { ask, done, gap, hint, link, live, say } from "@lib/term";

const out = process.env.RECORDINGS_DIR ?? `${homedir()}/Recordings`;
const models = `${homedir()}/.cache/whisper`;
// Pinned by checksum: a model is code whisper runs over every call.
const files = {
	speech: {
		name: "ggml-large-v3-turbo.bin",
		url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin",
		sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
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

export type Segment = { from: number; text: string };

/** One line per turn: [mm:ss] Who: text, consecutive segments of one speaker joined. */
export function merge(tracks: { who: string; segments: Segment[] }[]): string {
	const all = tracks
		.flatMap(({ who, segments }) => segments.map((s) => ({ who, ...s, text: s.text.trim() })))
		// [BLANK_AUDIO], (music) and the like are whisper's notes, not speech.
		.filter((s) => s.text && !/^[[(].*[\])]$/.test(s.text))
		.sort((a, b) => a.from - b.from);
	const turns: typeof all = [];
	for (const s of all) {
		const last = turns.at(-1);
		if (last?.who === s.who) last.text += ` ${s.text}`;
		else turns.push({ ...s });
	}
	return turns.map((t) => `[${clock(t.from)}] ${t.who ? `${t.who}: ` : ""}${t.text}\n`).join("");
}

const clock = (ms: number) => {
	const s = Math.floor(ms / 1000), h = Math.floor(s / 3600);
	const mmss = `${String(Math.floor(s / 60) % 60).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
	return h ? `${h}:${mmss}` : mmss;
};

/** The names of the people on a calendar event: its organizer and attendees. */
export function attendees(ics: string): string[] {
	const unfolded = ics.replace(/\r?\n[ \t]/g, ""); // a long line goes on after a newline and a space
	const names = [...unfolded.matchAll(/^(?:ATTENDEE|ORGANIZER)[^:\n]*?;CN=("?)([^";:\n]+)\1/gm)].map((m) => m[2].trim());
	return [...new Set(names)].filter((n) => !n.includes("@"));
}

/** A path dragged into a terminal arrives quoted or with escaped spaces. */
export const dropped = (s: string) => s.trim().replace(/^'(.*)'$/, "$1").replace(/^"(.*)"$/, "$1").replace(/\\(.)/g, "$1");

async function sha256(path: string) {
	const h = new Bun.CryptoHasher("sha256");
	for await (const chunk of Bun.file(path).stream()) h.update(chunk);
	return h.digest("hex");
}

async function setup() {
	if (!Bun.which("whisper-cli")) await $`brew install whisper.cpp`;
	for (const m of ["speech", "vad"] as const) {
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

function latest(): string {
	const recordings = readdirSync(out)
		.filter((f) => /\.(m4a|mp4)$/.test(f))
		.map((f) => join(out, f))
		.sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);
	if (!recordings[0]) throw new Error(`no recording in ${out}`);
	return recordings[0];
}

/** Transcribes a recording into <recording>.txt and returns that path. */
export async function transcribe(file = latest()): Promise<string> {
	if (!existsSync(file)) throw new Error(`no such recording: ${file}`);
	if (!existsSync(model("speech")) || !existsSync(model("vad"))) await setup();
	let ics = process.env.ICS ?? "";
	if (!ics && process.stdin.isTTY) ics = dropped(await ask("Calendar event (.ics), drag it here", "[Enter = none]"));
	const names = ics ? attendees(readFileSync(ics, "utf8")) : [];
	if (names.length) hint(`Names: ${names.join(", ")}`);

	// OBS tracks 1 = both mixed, 2 = the call, 3 = me, so audio streams 0, 1, 2.
	// A recording made otherwise is one voice.
	const count = (await $`ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 ${file}`.text()).trim().split("\n").length;
	const tracks = count >= 3 ? [{ who: "Them", track: 1 }, { who: "Me", track: 2 }] : [{ who: "", track: 0 }];
	const tmp = mkdtempSync(join(tmpdir(), "transcribe-"));
	try {
		const heard = [];
		for (const { who, track } of tracks) {
			live(`Transcribing ${who || "the recording"}`);
			const wav = `${tmp}/${track}.wav`;
			await $`ffmpeg -nostdin -loglevel error -i ${file} -map 0:a:${track} -ar 16000 -ac 1 -c:a pcm_s16le ${wav}`;
			const prompt = names.length ? ["--prompt", `${names.join(", ")}.`] : [];
			await $`whisper-cli -m ${model("speech")} --vad -vm ${model("vad")} -l ${process.env.SPOKEN || "auto"} ${prompt} -np -oj -of ${tmp}/${track} -f ${wav}`.quiet();
			const json = JSON.parse(readFileSync(`${tmp}/${track}.json`, "utf8"));
			heard.push({ who, segments: json.transcription.map((s: any) => ({ from: s.offsets.from, text: s.text })) });
		}
		const txt = file.replace(/\.[^.]*$/, ".txt");
		await Bun.write(txt, merge(heard));
		return txt;
	} finally {
		rmSync(tmp, { recursive: true });
	}
}

async function run(file?: string) {
	gap();
	const txt = await transcribe(file);
	if (!process.stdout.isTTY) return say(txt);
	gap();
	done(`Transcribed ${txt.split("/").at(-1)}`);
	say(`  ${link(txt)}`);
	gap();
}

if (import.meta.main) await cli(import.meta.path, { setup, run });
