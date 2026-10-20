// What transcript.ts would get wrong silently: the byte search returning a line
// twice or cut short, missing the last line when the file does not end in a
// newline, or taking a subagent's entry for the main conversation's.
import { afterAll, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { calls, entries } from "@lib/transcript";

const dir = mkdtempSync(join(tmpdir(), "transcript-"));
afterAll(() => rmSync(dir, { recursive: true }));

let n = 0;
function transcript(...lines: string[]) {
	const path = join(dir, `${n++}.jsonl`);
	writeFileSync(path, lines.join("\n"));
	return path;
}
const skill = (name: string, extra = {}) =>
	JSON.stringify({ type: "assistant", ...extra, message: { content: [{ type: "tool_use", name: "Skill", input: { skill: name } }] } });

test("every call, the last line read without a trailing newline", () =>
	expect(calls(transcript(skill("a"), '{"type":"user","message":{"content":"hi"}}', skill("ž")), "Skill"))
		.toEqual([{ skill: "a" }, { skill: "ž" }]));

test("a line with the marker twice is read once", () =>
	expect(entries(transcript(JSON.stringify({ type: "user", message: { content: "Skill and Skill" } })), "Skill"))
		.toHaveLength(1));

test("a subagent's entries, the harness's and broken lines are skipped", () =>
	expect(calls(transcript(skill("sub", { isSidechain: true }), '{"type":"system","Skill":1}', '{"Skill', skill("main")), "Skill"))
		.toEqual([{ skill: "main" }]));

test("no file is no entries", () => expect(calls(join(dir, "missing.jsonl"), "Skill")).toEqual([]));
