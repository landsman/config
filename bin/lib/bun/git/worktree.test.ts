// What withWorktree would get wrong silently: starting from the checkout's
// branch instead of the base, or leaving a worktree and a branch behind when
// the work fails.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { $ } from "bun";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { gitSandbox } from "@lib/git/testing/sandbox";
import { withWorktree } from "@lib/git/worktree";

let sandbox: Awaited<ReturnType<typeof gitSandbox>>;
let checkout: string;
beforeAll(async () => {
	sandbox = await gitSandbox();
	checkout = sandbox.checkout;
	// The checkout sits on a feature branch with a commit of its own and an
	// uncommitted edit: the worktree must see neither.
	await $`git -C ${checkout} switch --quiet -c feature`;
	writeFileSync(`${checkout}/other.txt`, "feature\n");
	await $`git -C ${checkout} add . && git -C ${checkout} commit --quiet -m feature`;
	writeFileSync(`${checkout}/settings.json`, "uncommitted\n");
});
afterAll(() => sandbox.remove());

describe("expected use", () => {
	test("the worktree starts from origin's default branch, not from the checkout", async () => {
		const seen = await withWorktree({ repo: checkout, branch: "setup/look" }, async (worktree) => ({
			base: worktree.base,
			settings: readFileSync(`${worktree.path}/settings.json`, "utf8"),
			other: existsSync(`${worktree.path}/other.txt`),
		}));
		expect(seen).toEqual({ base: "main", settings: "base\n", other: false });
	});
	test("the checkout is left as it was, its uncommitted edit included", async () => {
		expect(readFileSync(`${checkout}/settings.json`, "utf8")).toBe("uncommitted\n");
		expect((await $`git -C ${checkout} branch --show-current`.text()).trim()).toBe("feature");
	});
	test("no worktree and no local branch are left behind", async () => {
		expect(existsSync(`${checkout}/.claude/worktrees/setup-look`)).toBe(false);
		expect(await $`git -C ${checkout} branch --list setup/look`.text()).toBe("");
	});
});

describe("bad input", () => {
	test("work that throws still cleans up, and the error reaches the caller", async () => {
		const failing = withWorktree({ repo: checkout, branch: "setup/broken" }, async () => {
			throw new Error("broken work");
		});
		await expect(failing).rejects.toThrow("broken work");
		expect(existsSync(`${checkout}/.claude/worktrees/setup-broken`)).toBe(false);
		expect(await $`git -C ${checkout} branch --list setup/broken`.text()).toBe("");
	});
	test("a base origin does not have fails before any worktree exists", async () => {
		const missing = withWorktree(
			{ repo: checkout, branch: "setup/missing", base: "nope" },
			async () => 1,
		);
		await expect(missing).rejects.toThrow();
		expect(existsSync(`${checkout}/.claude/worktrees/setup-missing`)).toBe(false);
	});
});
