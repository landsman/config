// What the remote helpers would get wrong silently: a default branch assumed
// instead of read, or a push that left the branch untracked.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { $ } from "bun";
import { defaultBranch, push } from "@lib/git/remote";
import { gitSandbox } from "@lib/git/testing/sandbox";

let sandbox: Awaited<ReturnType<typeof gitSandbox>>;
beforeAll(async () => {
	sandbox = await gitSandbox();
});
afterAll(() => sandbox.remove());

describe("expected use", () => {
	test("the default branch is what origin's HEAD points at", async () => {
		expect(await defaultBranch(sandbox.checkout)).toBe("main");
		await $`git -C ${sandbox.origin} branch trunk main`;
		await $`git -C ${sandbox.origin} symbolic-ref HEAD refs/heads/trunk`;
		expect(await defaultBranch(sandbox.checkout)).toBe("trunk");
		await $`git -C ${sandbox.origin} symbolic-ref HEAD refs/heads/main`;
	});
	test("a pushed branch is on origin and tracked", async () => {
		await $`git -C ${sandbox.checkout} switch --quiet -c setup/pushed`;
		await push(sandbox.checkout, "setup/pushed");
		expect(await $`git -C ${sandbox.origin} branch --list setup/pushed`.text()).toContain(
			"setup/pushed",
		);
		const upstream = await $`git -C ${sandbox.checkout} rev-parse --abbrev-ref @{upstream}`.text();
		expect(upstream.trim()).toBe("origin/setup/pushed");
	});
});

describe("bad input", () => {
	test("a repo with no origin fails instead of guessing main", async () => {
		await $`git -C ${sandbox.scratch} init --quiet lonely`;
		expect(defaultBranch(`${sandbox.scratch}/lonely`)).rejects.toThrow();
	});
});
