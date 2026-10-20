// What term.ts would get wrong silently: a colour code or the indent leaking
// into output a script reads, which breaks every `p=$(…)` built on it.
import { expect, test } from "bun:test";
import { createTerm } from "@lib/term";

const capture = (tty: boolean) => {
	const lines: string[] = [];
	return { lines, stream: { tty, write: (s: string) => lines.push(s) } };
};

test("piped output is bare: no colour, no indent, no link", () => {
	const out = capture(false), err = capture(false);
	const t = createTerm(out.stream, err.stream);
	t.done("Saved x.m4a", "1.2 MB");
	t.say(t.link("/tmp/x.m4a"));
	t.warn("broken");
	expect(out.lines).toEqual(["✓ Saved x.m4a  1.2 MB\n", "/tmp/x.m4a\n"]);
	expect(err.lines).toEqual(["✗ broken\n"]);
});

test("a terminal gets the indent, colour and a ⌘-clickable link", () => {
	const out = capture(true);
	const t = createTerm(out.stream, capture(false).stream);
	t.say(t.link("/tmp/a b.m4a"));
	expect(out.lines[0]).toBe("  \x1b]8;;file:///tmp/a%20b.m4a\x1b\\/tmp/a b.m4a\x1b]8;;\x1b\\\n");
	t.live("Recording");
	expect(out.lines[1]).toBe("  \x1b[1;31m●\x1b[0m \x1b[1mRecording\x1b[0m\n");
});

test("stdout and stderr are judged apart", () => {
	const out = capture(false), err = capture(true);
	const t = createTerm(out.stream, err.stream);
	t.done("ok");
	t.warn("no");
	expect(out.lines[0]).toBe("✓ ok\n");
	expect(err.lines[0]).toBe("  \x1b[1;31m✗ no\x1b[0m\n");
});
