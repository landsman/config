// What proc.ts would get wrong silently: retrying an error it was told not to,
// swallowing the last error, or waiting past its limit. The waits are a second
// each, so each case needs at most one.
import { expect, test } from "bun:test";
import { retry, running, waitFor } from "@lib/proc";

test("running sees this test's own process, and not a made-up one", async () => {
	expect(await running("bun")).toBe(true);
	expect(await running("no-such-process-anywhere-42")).toBe(false);
});

test("waitFor says when the condition came true", async () => {
	let checks = 0;
	expect(await waitFor(async () => ++checks >= 2, 5)).toBe(true);
	expect(checks).toBe(2);
});

test("waitFor gives up after its seconds, checking once more at the end", async () => {
	let checks = 0;
	expect(await waitFor(async () => (checks++, false), 1)).toBe(false);
	expect(checks).toBe(2);
});

test("retry returns the first success", async () => {
	let tries = 0;
	expect(await retry(async () => { if (++tries < 2) throw new Error("not yet"); return "ok"; }, 5)).toBe("ok");
});

test("retry throws the error it may not retry, at once", async () => {
	let tries = 0;
	const fail = retry(async () => { tries++; throw new Error("fatal"); }, 5, (e) => e.message !== "fatal");
	expect(fail).rejects.toThrow("fatal");
	await fail.catch(() => {});
	expect(tries).toBe(1);
});
