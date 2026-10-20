// What transcript.ts would get wrong silently: the byte search returning a line
// twice or cut short, missing the last line when the file does not end in a
// newline, or taking a subagent's entry for the main conversation's.
import { afterAll, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { calls, content, entries, lastTurn } from "@lib/transcript";

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

const prompt = (text: string) => JSON.stringify({ type: "user", message: { content: text } });
const say = (text: string) => JSON.stringify({ type: "assistant", message: { content: [{ type: "text", text }] } });
const toolResult = JSON.stringify({ type: "user", message: { content: [{ type: "tool_result", content: "ok" }] } });
const reminder = JSON.stringify({ type: "user", isMeta: true, message: { content: [{ type: "text", text: "reminder" }] } });
const texts = (path: string) => lastTurn(path).flatMap(content).map((b) => b.text ?? b.type);

test("the last turn starts after the last prompt, tool results and reminders inside it", () =>
	expect(texts(transcript(prompt("one"), say("a"), prompt("two"), say("b"), toolResult, reminder, say("c"))))
		.toEqual(["b", "tool_result", "reminder", "c"]));
test("the last turn of a file ending in a newline", () =>
	expect(texts(transcript(prompt("one"), say("a"), ""))).toEqual(["a"]));
test("no prompt at all is the whole file", () => expect(texts(transcript(say("a"), say("b")))).toEqual(["a", "b"]));
