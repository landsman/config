// What hook.ts would get wrong silently: a hook that crashes on input that is
// not JSON (Claude Code shows that as an error on every prompt), or an answer
// that is not one JSON line.
import { expect, test } from "bun:test";
import { join } from "node:path";

/** What a hook built on event() and answer() prints for this stdin. */
async function echo(stdin: string) {
	const lib = join(import.meta.dir, "hook.ts");
	const proc = Bun.spawn([process.execPath, "-e",
		`import { answer, event } from ${JSON.stringify(lib)}; const e = await event(); if (e) answer({ got: e });`],
	{ stdin: new Blob([stdin]) });
	const out = await new Response(proc.stdout).text();
	expect(await proc.exited).toBe(0);
	return out;
}

test("the event arrives parsed, the answer leaves as one JSON line", async () =>
	expect(await echo('{"prompt":"ahoj ž"}')).toBe('{"got":{"prompt":"ahoj ž"}}\n'));
test("input that is not JSON is no event, not a crash", async () => expect(await echo("not json")).toBe(""));
test("no input is no event", async () => expect(await echo("")).toBe(""));
