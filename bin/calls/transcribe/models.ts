// The models a transcript runs on, installed once and checked before each use:
// whisper.cpp's, pinned by checksum, and the FluidAudio diarizer, built from a
// pinned commit with its models checked as one tree.
import { $ } from "bun";
import { existsSync, mkdtempSync, readdirSync, renameSync, rmSync, statSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { done, live, warn } from "@lib/term";

export enum WhisperModel {
	Quick = "quick",
	Precise = "precise",
	SilenceDetector = "silence-detector",
}

export function whisperModelPath(model: WhisperModel): string {
	return `${whisperModelsFolder}/${whisperModels[model].file}`;
}

export async function setup() {
	if (!Bun.which("whisper-cli")) {
		await $`brew install whisper.cpp`;
	}
	for (const model of Object.values(WhisperModel)) {
		await downloadWhisperModel(model);
	}
	done("whisper.cpp is set up", whisperModelsFolder);

	if (!Bun.which("swift")) {
		return warn("swift is missing (install Xcode): transcripts keep one Them, unsplit by voice");
	}
	if (!existsSync(diarizer.program)) {
		await buildDiarizer();
	}
	if (!(await diarizerModelsReady())) {
		await downloadDiarizerModels();
	}
	// An earlier setup put the models where the program never looks; gone only when they are exactly ours.
	const misplaced = diarizer.misplacedModelsFolder;
	if (existsSync(misplaced) && (await diarizerModelsReady(misplaced))) {
		rmSync(misplaced, { recursive: true });
	}
	done("FluidAudio is set up", diarizer.program);
}

async function downloadWhisperModel(model: WhisperModel) {
	const { file, url, checksum } = whisperModels[model];
	const destination = whisperModelPath(model);
	if (existsSync(destination)) {
		return;
	}
	await checkHuggingFaceAllows(url, whisperModelsFolder);
	live(`Downloading ${file}`);
	const partial = `${destination}.part`;
	await $`mkdir -p ${whisperModelsFolder} && curl -fL --progress-bar -o ${partial} ${url}`;
	if ((await fileChecksum(partial)) !== checksum) {
		rmSync(partial);
		throw new Error(`${file} does not match its checksum, deleted`);
	}
	renameSync(partial, destination);
}

/**
 * A network that filters the web (a work laptop) often blocks Hugging Face,
 * and curl then says only "error: 403". One HEAD request, redirects followed
 * to the file storage, says it before a 4.7 GB download and says what to do.
 */
export async function checkHuggingFaceAllows(url: string, modelsFolder: string) {
	const answer = await fetch(url, { method: "HEAD" }).then(
		(response) => (response.ok ? undefined : `answered ${response.status}`),
		(error: Error) => `could not be reached (${error.message})`,
	);
	if (answer === undefined) {
		return;
	}
	throw new Error(
		[
			`Hugging Face ${answer}, so this network probably blocks it.`,
			"Download the models on another network (make record-init there),",
			`then copy them into ${modelsFolder} here and run it again.`,
			"Or ask IT to allow huggingface.co and *.hf.co.",
		].join("\n"),
	);
}

async function fileChecksum(path: string): Promise<string> {
	const hasher = new Bun.CryptoHasher("sha256");
	for await (const chunk of Bun.file(path).stream()) {
		hasher.update(chunk);
	}
	return hasher.digest("hex");
}

async function buildDiarizer() {
	live(`Building FluidAudio ${diarizer.tag}, once`);
	const sourceFolder = mkdtempSync(join(tmpdir(), "fluidaudio-"));
	try {
		await $`git -c advice.detachedHead=false clone -q --depth 1 --branch ${diarizer.tag} https://github.com/FluidInference/FluidAudio.git ${sourceFolder}`;
		const commit = (await $`git -C ${sourceFolder} rev-parse HEAD`.text()).trim();
		if (commit !== diarizer.commit) {
			throw new Error(
				`FluidAudio ${diarizer.tag} is ${commit} now, not ${diarizer.commit}: the tag moved`,
			);
		}
		await $`swift build -c release --product fluidaudiocli --package-path ${sourceFolder}`.quiet();
		const built = `${sourceFolder}/.build/release/fluidaudiocli`;
		await $`mkdir -p ${dirname(diarizer.program)} && cp ${built} ${diarizer.program}`;
	} finally {
		rmSync(sourceFolder, { recursive: true });
	}
}

/** Whether the models on disk are exactly the pinned ones, and marked as that revision for the program. */
export async function diarizerModelsReady(folder = diarizer.modelsFolder): Promise<boolean> {
	if (!existsSync(`${folder}/.fluidaudio-revision`)) {
		return false;
	}
	return (await folderChecksum(folder)) === diarizer.modelsChecksum;
}

/** The checksum of every model file, sorted by path, checksummed again: shasum -a 256 over a tree. */
async function folderChecksum(folder: string): Promise<string> {
	const modelFiles = readdirSync(folder, { recursive: true, encoding: "utf8" })
		.filter((path) => diarizer.modelFiles.test(path) && statSync(join(folder, path)).isFile())
		.sort((first, second) => (first < second ? -1 : first > second ? 1 : 0));
	let checksums = "";
	for (const path of modelFiles) {
		checksums += `${await fileChecksum(join(folder, path))}  ${path}\n`;
	}
	return new Bun.CryptoHasher("sha256").update(checksums).digest("hex");
}

async function downloadDiarizerModels() {
	live("Downloading the diarization models (22 MB)");
	const listing = `https://huggingface.co/api/models/${diarizer.repository}/revision/${diarizer.revision}`;
	await checkHuggingFaceAllows(listing, diarizer.modelsFolder);
	const { siblings: repositoryFiles } = (await (await fetch(listing)).json()) as {
		siblings: { rfilename: string }[];
	};
	const modelFiles = repositoryFiles
		.map((repositoryFile) => repositoryFile.rfilename)
		.filter((path) => diarizer.modelFiles.test(path));

	const partial = `${diarizer.modelsFolder}.part`;
	rmSync(partial, { recursive: true, force: true });
	for (const path of modelFiles) {
		const url = `https://huggingface.co/${diarizer.repository}/resolve/${diarizer.revision}/${path}`;
		const destination = `${partial}/${path}`;
		await $`mkdir -p ${dirname(destination)} && curl -fsSL -o ${destination} ${url}`;
	}
	if ((await folderChecksum(partial)) !== diarizer.modelsChecksum) {
		rmSync(partial, { recursive: true });
		throw new Error("the diarization models do not match their checksum, deleted");
	}
	// The program takes a folder marked with its own pinned revision as downloaded.
	await Bun.write(`${partial}/.fluidaudio-revision`, diarizer.revision);
	rmSync(diarizer.modelsFolder, { recursive: true, force: true });
	renameSync(partial, diarizer.modelsFolder);
}

const whisperModelsFolder = `${homedir()}/.cache/whisper`;

// Pinned by checksum: a model is code whisper runs over every call.
const whisperModels: Record<WhisperModel, { file: string; url: string; checksum: string }> = {
	// Turbo is large-v3 with 4 decoder layers instead of 32: several times
	// faster, and it loses the most on languages other than English.
	[WhisperModel.Quick]: {
		file: "ggml-large-v3-turbo.bin",
		url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin",
		checksum: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
	},
	[WhisperModel.Precise]: {
		file: "ggml-large-v3.bin",
		url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin",
		checksum: "64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2",
	},
	// Silence goes to whisper as nothing at all; fed to it, it makes up
	// sentences ("Titulky vytvořil…"), and a muted mic is mostly silence.
	[WhisperModel.SilenceDetector]: {
		file: "ggml-silero-v6.2.0.bin",
		url: "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v6.2.0.bin",
		checksum: "2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987",
	},
};

// The diarizer is built from a pinned commit, and that commit pins its models'
// revision; the models are checked against one checksum over all their files
// before the program ever loads them. No release ships a binary.
export const diarizer = {
	tag: "v0.17.7",
	commit: "503b4bd1bbf7220882de39fe8ae6716aae4132da",
	program: `${homedir()}/.cache/fluidaudio/fluidaudiocli-0.17.7`,
	repository: "FluidInference/speaker-diarization-coreml",
	revision: "df2625ac79a7ac6b65ad868fee6d80f320da4232",
	modelsChecksum: "ff077a5564c55aa1063dfb4ae11d472f80190f380ae9602686f5ce8420863c12",
	// The repository's name without -coreml, as FluidAudio's Repo.folderName makes it
	modelsFolder: `${homedir()}/Library/Application Support/FluidAudio/Models/speaker-diarization`,
	misplacedModelsFolder: `${homedir()}/Library/Application Support/FluidAudio/Models/speaker-diarization-coreml`,
	modelFiles: /^(Segmentation|FBank|Embedding|PldaRho)\.mlmodelc\/|^plda-parameters\.json$/,
};
