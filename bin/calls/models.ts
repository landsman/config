// The models a transcript runs on, installed once and checked before each use:
// whisper.cpp's, pinned by checksum, and the FluidAudio diarizer, built from a
// pinned commit with its models checked as one tree.
import { $ } from "bun";
import { existsSync, mkdtempSync, readdirSync, renameSync, rmSync, statSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { done, live, warn } from "@lib/term";

async function sha256(path: string) {
	const h = new Bun.CryptoHasher("sha256");
	for await (const chunk of Bun.file(path).stream()) h.update(chunk);
	return h.digest("hex");
}

export async function setup() {
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
	// An earlier setup put the models where the CLI never looks; gone only when they are exactly ours.
	if (existsSync(fluid.misplaced) && (await fluidReady(fluid.misplaced))) rmSync(fluid.misplaced, { recursive: true });
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
export async function fluidReady(dir = fluid.dir) {
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
export const model = (m: keyof typeof files) => `${models}/${files[m].name}`;

// The diarizer is built from a pinned commit, and that commit pins its models'
// revision; the models are checked against one hash over all their files
// before the CLI ever loads them. No release ships a binary.
export const fluid = {
	tag: "v0.17.7",
	commit: "503b4bd1bbf7220882de39fe8ae6716aae4132da",
	bin: `${homedir()}/.cache/fluidaudio/fluidaudiocli-0.17.7`,
	repo: "FluidInference/speaker-diarization-coreml",
	revision: "df2625ac79a7ac6b65ad868fee6d80f320da4232",
	// shasum -a 256 of every file, sorted by path, hashed again
	tree: "ff077a5564c55aa1063dfb4ae11d472f80190f380ae9602686f5ce8420863c12",
	// The repository's name without -coreml, as FluidAudio's Repo.folderName makes it
	dir: `${homedir()}/Library/Application Support/FluidAudio/Models/speaker-diarization`,
	misplaced: `${homedir()}/Library/Application Support/FluidAudio/Models/speaker-diarization-coreml`,
	files: /^(Segmentation|FBank|Embedding|PldaRho)\.mlmodelc\/|^plda-parameters\.json$/,
};
