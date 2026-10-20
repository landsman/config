// Files a script installs from the repo, for the scripts under bin/.
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

/** Copies every file under src into dst, keeping the layout and replacing each
 *  placeholder (e.g. @RECORDINGS@) with its value. A path in `keep` (relative,
 *  like "user.ini") is copied only when dst has none yet. */
export function copyTree(src: string, dst: string, values: Record<string, string> = {}, keep: string[] = []) {
	for (const f of readdirSync(src, { recursive: true, encoding: "utf8" })) {
		const from = `${src}/${f}`, to = `${dst}/${f}`;
		if (statSync(from).isDirectory() || (keep.includes(f) && existsSync(to))) continue;
		let text = readFileSync(from, "utf8");
		for (const [k, v] of Object.entries(values)) text = text.replaceAll(k, v);
		mkdirSync(dirname(to), { recursive: true });
		writeFileSync(to, text);
	}
}
