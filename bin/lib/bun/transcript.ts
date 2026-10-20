// Reading a Claude Code session transcript, one JSON entry per line, for the
// hook scripts under bin/agents/. A transcript runs to a hundred MB, so nothing
// here parses all of it: only the lines that can matter are decoded.
import { readFileSync } from "node:fs";

export type Block = { type?: string; text?: string; name?: string; input?: Record<string, unknown> };
export type Entry = { type?: string; isSidechain?: boolean; isMeta?: boolean; message?: { content?: string | Block[] } };

const NEWLINE = 10;

/** The main conversation's entries on the lines containing `marker`. */
export const entries = (path: string | undefined, marker: string): Entry[] =>
	linesWith(path, marker).flatMap((line) => mainEntry(line) ?? []);

/** The main conversation's entries since the last prompt the user typed, oldest first. */
export function lastTurn(path: string | undefined): Entry[] {
	const turn: Entry[] = [];
	for (const line of linesFromEnd(path)) {
		const entry = mainEntry(line);
		if (!entry) continue;
		if (isPrompt(entry)) break;
		turn.unshift(entry);
	}
	return turn;
}

/** The input of every call the model made to `tool` in the session. */
export const calls = (path: string | undefined, tool: string) =>
	entries(path, `"${tool}"`).flatMap(content).filter((b) => b.name === tool).map((b) => b.input ?? {});

/** An entry's content as blocks; a plain string is one text block. */
export function content(entry: Entry): Block[] {
	const c = entry.message?.content;
	return typeof c === "string" ? [{ type: "text", text: c }] : Array.isArray(c) ? c : [];
}

/** A prompt the user typed, not a tool result or a reminder the harness injected. */
export const isPrompt = (entry: Entry) =>
	entry.type === "user" && !entry.isMeta && content(entry).some((b) => b.type === "text" || b.type === "image");

/** A user or assistant entry of the main conversation; not a subagent's
 *  (sidechain), not the harness's bookkeeping, not a broken line. */
function mainEntry(line: string): Entry | undefined {
	try {
		const entry: Entry = JSON.parse(line);
		return (entry.type === "user" || entry.type === "assistant") && !entry.isSidechain ? entry : undefined;
	} catch {
		return undefined;
	}
}

function read(path: string | undefined): Buffer | undefined {
	try {
		return readFileSync(path ?? "");
	} catch {
		return undefined;
	}
}

/** The lines containing `marker`, found in the raw bytes: on a 13 MB transcript
 *  a third of the time of decoding and splitting it all. */
function linesWith(path: string | undefined, marker: string): string[] {
	const bytes = read(path);
	const lines: string[] = [];
	for (let at = bytes?.indexOf(marker) ?? -1; bytes && at !== -1; ) {
		const start = bytes.lastIndexOf(NEWLINE, at) + 1;
		let end = bytes.indexOf(NEWLINE, at);
		if (end === -1) end = bytes.length;
		lines.push(bytes.toString("utf8", start, end));
		at = bytes.indexOf(marker, end + 1);
	}
	return lines;
}

/** The lines from the last one back, decoded only as far as the caller reads. */
function* linesFromEnd(path: string | undefined): Generator<string> {
	const bytes = read(path);
	for (let end = bytes?.length ?? 0; bytes && end > 0; ) {
		const start = bytes.lastIndexOf(NEWLINE, end - 1) + 1;
		yield bytes.toString("utf8", start, end);
		end = start - 1;
	}
}
