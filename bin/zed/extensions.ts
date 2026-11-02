// Adds every extension installed in Zed to `auto_install_extensions` in the
// repo's Zed settings, which is what installs them on the next machine.
// Installing from Zed's UI writes nothing to that list, so it drifts.
//
// Only adds: an entry already there stays as it is, `false` included, and one
// for an extension not installed here is kept — another machine may want it.
//
// usage: extensions.ts sync   add this machine's extensions to the settings
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { cli } from "@lib/cli";

const settingsPath = `${import.meta.dir}/../../shared/.config/zed/settings.json`;

if (import.meta.main) {
	await cli(import.meta.path, { sync });
}

async function sync() {
	const { text, added } = addExtensions(readFileSync(settingsPath, "utf8"), installedExtensions());
	// Written in place: ~/.config/zed/settings.json is a symlink to this file.
	writeFileSync(settingsPath, text);
	console.log(added.length ? added.map((id) => `added ${id}`).join("\n") : "nothing to add");
}

function installedExtensions() {
	const dir =
		process.platform === "darwin"
			? `${homedir()}/Library/Application Support/Zed/extensions/installed`
			: `${process.env.XDG_DATA_HOME ?? `${homedir()}/.local/share`}/zed/extensions/installed`;
	if (!existsSync(dir)) throw new Error(`no Zed extensions in ${dir}`);
	return readdirSync(dir, { withFileTypes: true })
		.filter((entry) => entry.isDirectory())
		.map((entry) => entry.name)
		.sort();
}

/** The file is JSONC (comments, trailing commas), so this edits lines rather
 *  than parsing: the block is one flat `"id": bool` per line, as Zed writes it. */
export function addExtensions(settings: string, ids: string[]) {
	const lines = settings.split("\n");
	const start = lines.findIndex((line) => /"auto_install_extensions"\s*:\s*\{/.test(line));
	const end = lines.findIndex((line, index) => index > start && /^\s*\}/.test(line));
	if (start < 0 || end < 0) throw new Error("no auto_install_extensions block in the Zed settings");
	const listed = new Set(
		lines.slice(start + 1, end).flatMap((line) => line.match(/"([^"]+)"\s*:/)?.[1] ?? []),
	);
	const added = ids.filter((id) => !listed.has(id));
	if (!added.length) return { text: settings, added };
	const last = end - 1;
	// Without it Zed rejects the whole file, not just the block.
	if (!/[,{]\s*$/.test(lines[last]!)) lines[last] += ",";
	const entries = added.map(
		(id, index) => `    "${id}": true${index < added.length - 1 ? "," : ""}`,
	);
	lines.splice(end, 0, ...entries);
	return { text: lines.join("\n"), added };
}
