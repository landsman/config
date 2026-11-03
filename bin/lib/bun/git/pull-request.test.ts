// What openPullRequest would get wrong silently: a commit that carries more
// than the change, a push that never happened, or a pull request opened for
// nothing. The worktree itself is worktree.test.ts's.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { $ } from "bun";
import { writeFileSync } from "node:fs";
import { openPullRequest } from "@lib/git/pull-request";
import { stubGh } from "@lib/git/testing/gh-stub";
import { gitSandbox } from "@lib/git/testing/sandbox";

let sandbox: Awaited<ReturnType<typeof gitSandbox>>;
let gh: ReturnType<typeof stubGh>;
beforeAll(async () => {
	sandbox = await gitSandbox();
	gh = stubGh(sandbox.scratch, "https://github.com/owner/repo/pull/1");
});
afterAll(() => sandbox.remove());

describe("expected use", () => {
	test("the change is one commit on the base, pushed, with a pull request", async () => {
		const url = await openPullRequest({
			repo: sandbox.checkout,
			branch: "setup/change",
			change: async (worktree) => {
				writeFileSync(`${worktree}/settings.json`, "changed\n");
				return { paths: ["settings.json"], title: "setup: change it", body: "because" };
			},
		});
		expect(url).toBe("https://github.com/owner/repo/pull/1");
		const pushed = await $`git -C ${sandbox.origin} log --format=%s main..setup/change`.text();
		expect(pushed).toBe("setup: change it\n");
		expect(gh.calls()).toContain(
			"--base\nmain\n--head\nsetup/change\n--title\nsetup: change it\n--body\nbecause\n",
		);
	});
});

describe("bad input", () => {
	test("nothing to commit opens nothing and pushes nothing", async () => {
		const before = gh.calls();
		const url = await openPullRequest({
			repo: sandbox.checkout,
			branch: "setup/nothing",
			change: async () => undefined,
		});
		expect(url).toBeUndefined();
		expect(gh.calls()).toBe(before);
		expect(await $`git -C ${sandbox.origin} branch --list setup/nothing`.text()).toBe("");
	});

	test("a title that breaks the commit convention opens nothing and pushes nothing", async () => {
		const before = gh.calls();
		const opening = openPullRequest({
			repo: sandbox.checkout,
			branch: "setup/capitalised",
			change: async (worktree) => {
				writeFileSync(`${worktree}/settings.json`, "capitalised\n");
				return { paths: ["settings.json"], title: "Change it", body: "because" };
			},
		});
		await expect(opening).rejects.toThrow(/got: {6}Change it/);
		expect(gh.calls()).toBe(before);
		expect(await $`git -C ${sandbox.origin} branch --list setup/capitalised`.text()).toBe("");
	});
});
