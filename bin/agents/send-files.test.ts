// What send-files.ts would get wrong silently: letting a named screenshot through
// unsent, holding a turn for a file already sent or one that does not exist, or
// holding the same turn twice. Small transcripts written here, in the shape
// Claude Code writes them.
import { afterAll, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runHook } from "@lib/testing";

const hook = join(import.meta.dir, "send-files.ts");
const dir = mkdtempSync(join(tmpdir(), "send-files-"));
afterAll(() => rmSync(dir, { recursive: true }));
const shot = join(dir, "shot.png");
writeFileSync(shot, "");
writeFileSync(join(dir, "Main.kt"), "");

const prompt = (text: string) => ({ type: "user", message: { role: "user", content: text } });
const say = (text: string) => ({ type: "assistant", message: { role: "assistant", content: [{ type: "text", text }] } });
const send = (file: string) =>
	({ type: "assistant", message: { role: "assistant", content: [{ type: "tool_use", name: "SendUserFile", input: { files: [file] } }] } });
const result = { type: "user", message: { role: "user", content: [{ type: "tool_result", content: "ok" }] } };

/** Whether the hook holds the turn that ends this transcript. */
async function holds(lines: object[], stopHookActive = false) {
	const transcript = join(dir, "transcript.jsonl");
	writeFileSync(transcript, lines.map((l) => JSON.stringify(l)).join("\n") + "\n");
	const answer = await runHook(hook, { transcript_path: transcript, stop_hook_active: stopHookActive });
	return answer?.decision === "block";
}

test("a screenshot named but never sent holds the turn", async () =>
	expect(await holds([prompt("ukaz to"), say(`Snímek je v ${shot}.`)])).toBe(true));
test("a screenshot sent in the same turn passes", async () =>
	expect(await holds([prompt("ukaz to"), send(shot), result, say(`Poslal jsem ${shot}.`)])).toBe(false));
test("a screenshot sent in an earlier turn passes", async () =>
	expect(await holds([prompt("ukaz to"), send(shot), result, say("hotovo"), prompt("a dal?"), say(`Pořád platí ${shot}.`)])).toBe(false));
test("a path that does not exist passes", async () =>
	expect(await holds([prompt("ukaz to"), say(`Snímek bude v ${dir}/later.png.`)])).toBe(false));
test("a source file is a reference and passes", async () =>
	expect(await holds([prompt("kde to je"), say(`Viz ${dir}/Main.kt:12.`)])).toBe(false));
test("the stop after a block is let through", async () =>
	expect(await holds([prompt("ukaz to"), say(`Snímek je v ${shot}.`)], true)).toBe(false));
test("a path named in an earlier turn only passes", async () =>
	expect(await holds([prompt("ukaz to"), say(`Snímek je v ${shot}.`), prompt("dalsi"), say("hotovo")])).toBe(false));
test("a path in backticks after a tool result still counts", async () =>
	expect(await holds([prompt("ukaz to"), result, say(`Snímek: \`${shot}\``)])).toBe(true));
