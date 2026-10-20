// What relay.ts would get wrong silently: a run taking another turn's state, a
// wait that never gives up and stalls the run past its caller's timeout, state
// left behind, or a file other users can read (it holds what a reply showed).
import { afterAll, expect, test } from "bun:test";
import { existsSync, mkdtempSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { awaitTurn, endRelay, passTurn, relayFile } from "@lib/relay";

const dir = mkdtempSync(join(tmpdir(), "relay-"));
process.env.TMPDIR = dir;
afterAll(() => rmSync(dir, { recursive: true }));

let n = 0;
const fresh = () => relayFile("relay-test", `r${n++}`);

test("the next turn gets the state the previous one passed", async () => {
	const file = fresh();
	passTurn(file, 0, { fence: "```" });
	expect(await awaitTurn(file, 1, 1)).toEqual({ fence: "```" });
});

test("a turn waits for the previous one to pass", async () => {
	const file = fresh();
	setTimeout(() => passTurn(file, 0, "late"), 50);
	expect(await awaitTurn(file, 1, 1)).toBe("late");
});

test("a turn does not take a state meant for another", async () => {
	const file = fresh();
	passTurn(file, 0, "for turn 1");
	expect(await awaitTurn(file, 2, 0.1)).toBeUndefined();
});

test("a wait gives up after its seconds", async () => {
	const start = performance.now();
	expect(await awaitTurn(fresh(), 1, 0.2)).toBeUndefined();
	expect(performance.now() - start).toBeLessThan(1000);
});

test("the relay is private to this user", () => {
	const file = fresh();
	passTurn(file, 0, {});
	expect(statSync(file).mode & 0o777).toBe(0o600);
	expect(statSync(dirname(file)).mode & 0o777).toBe(0o700);
});

test("ending a relay leaves nothing, and ending it twice is fine", () => {
	const file = fresh();
	passTurn(file, 0, {});
	endRelay(file);
	endRelay(file);
	expect(existsSync(file)).toBe(false);
});
