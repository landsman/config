// Reading a Claude Code session transcript, one JSON entry per line, for the
// hook scripts under bin/agents/.
import { readFileSync } from "node:fs";

export type Block = { type?: string; text?: string; name?: string; input?: Record<string, unknown> };
export type Entry = { type?: string; isSidechain?: boolean; isMeta?: boolean; message?: { content?: string | Block[] } };

/** The main conversation's entries on the lines containing `marker`. A
 *  transcript runs to a hundred MB, so only the lines that can matter are
 *  parsed; a subagent's own entries (sidechains) are left out. */
export function entries(path: string | undefined, marker: string): Entry[] {
	return linesWith(path, marker).flatMap((line) => {
		try {
			const e: Entry = JSON.parse(line);
			return (e.type === "user" || e.type === "assistant") && !e.isSidechain ? [e] : [];
		} catch {
			return [];
		}
	});
}

/** The lines of a file that contain `marker`; none when it cannot be read. The
 *  search runs over the raw bytes and only matching lines are decoded, which on
 *  a 13 MB transcript is a third of the time of decoding and splitting it all. */
function linesWith(path: string | undefined, marker: string): string[] {
	let bytes: Buffer;
	try {
		bytes = readFileSync(path ?? "");
	} catch {
		return [];
	}
	const lines: string[] = [];
	for (let at = bytes.indexOf(marker); at !== -1; ) {
		const start = bytes.lastIndexOf(10, at) + 1; // 10 = "\n"
		let end = bytes.indexOf(10, at);
		if (end === -1) end = bytes.length;
		lines.push(bytes.toString("utf8", start, end));
		at = bytes.indexOf(marker, end + 1);
	}
	return lines;
}

/** An entry's content as blocks; a plain string is one text block. */
export function content(entry: Entry): Block[] {
	const c = entry.message?.content;
	return typeof c === "string" ? [{ type: "text", text: c }] : Array.isArray(c) ? c : [];
}

/** The input of every call the model made to `tool` in the session. */
export const calls = (path: string | undefined, tool: string) =>
	entries(path, `"${tool}"`).flatMap(content).filter((b) => b.name === tool).map((b) => b.input ?? {});
