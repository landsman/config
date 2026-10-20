// What quote-to-fence.ts would get wrong silently: a quote left with its `> `,
// a fence of the message's own taken for a quote, a block left open across
// batches, or a lost batch stalling the rest of the message. One message is split
// over several batches started together, as Claude Code 2.1.296 does, and the
// joined display is compared.
import { afterAll, expect, test } from "bun:test";
import { mkdtempSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runHook } from "@lib/testing";

const hook = join(import.meta.dir, "quote-to-fence.ts");
const dir = mkdtempSync(join(tmpdir(), "quote-to-fence-"));
afterAll(() => rmSync(dir, { recursive: true }));

const batch = (message: string, index: number, final: boolean, delta: string) =>
	runHook(hook, { message_id: message, index, final, delta }, { TMPDIR: dir });

/** What the user sees of a message sent in these batches, all started at once. */
async function shown(message: string, ...batches: string[]) {
	const answers = await Promise.all(batches.map((delta, i) => batch(message, i, i === batches.length - 1, delta)));
	return answers.map((a, i) => a?.hookSpecificOutput.displayContent ?? batches[i]).join("");
}

test("a quote becomes a fenced block", async () =>
	expect(await shown("m1", "Hi\n> Dobrý den,\n> [odkaz](https://x.cz)\nend"))
		.toBe("Hi\n```markdown\nDobrý den,\n[odkaz](https://x.cz)\n```\nend"));
test("a quote run over three batches stays one block", async () =>
	expect(await shown("m2", "> a\n", "> b\n", "> c\nend")).toBe("```markdown\na\nb\nc\n```\nend"));
test("a run still open at the end is closed", async () =>
	expect(await shown("m3", "x\n", "> a")).toBe("x\n```markdown\na\n```\n"));
test("a > inside the message's own fence is content", async () =>
	expect(await shown("m4", "```bash\n", "> inside\n", "```\n> q\n")).toBe("```bash\n> inside\n```\n```markdown\nq\n```\n"));
test("a four-backtick fence holds a three-backtick one", async () =>
	expect(await shown("m5", "````md\n```\n", "> nested\n```\n````\n")).toBe("````md\n```\n> nested\n```\n````\n"));
test("a quote holding backticks gets a longer fence", async () =>
	expect(await shown("m6", "> run ```make```")).toBe("````markdown\nrun ```make```\n````\n"));
test("a nested list quote loses its marker", async () =>
	expect(await shown("m7", "- item\n  > note\n")).toBe("- item\n```markdown\nnote\n```\n"));
test("plain text is left alone", async () =>
	expect(await shown("m8", "a > b\n    > indented code\n")).toBe("a > b\n    > indented code\n"));

test("a lost batch passes the rest through, once, within the wait", async () => {
	const start = performance.now();
	expect(await batch("m9", 3, false, "> late\n")).toBeUndefined(); // batches 0-2 never ran
	expect(performance.now() - start).toBeLessThan(7000);
	expect(await batch("m9", 4, true, "> later\n")).toBeUndefined();
}, 15_000);

test("no state is left behind", () => expect(readdirSync(join(dir, "claude-quote-to-fence"))).toEqual([]));
