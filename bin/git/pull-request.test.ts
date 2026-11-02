// What openPullRequest would get wrong silently: committing on top of the
// checkout's branch instead of the base, touching the checkout, or leaving a
// worktree and a branch behind. Git is real, against a local bare origin;
// `gh` is a stub on PATH that records its arguments.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { $ } from "bun";
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { openPullRequest } from "@bin/git/pull-request";

const scratch = mkdtempSync(`${tmpdir()}/pull-request-`);
const checkout = `${scratch}/checkout`;
const ghCalls = `${scratch}/gh-calls`;

beforeAll(async () => {
	// No hooks and no identity from this machine's .gitconfig.
	Object.assign(process.env, {
		GIT_CONFIG_GLOBAL: "/dev/null",
		GIT_CONFIG_NOSYSTEM: "1",
		GIT_AUTHOR_NAME: "test",
		GIT_AUTHOR_EMAIL: "test@example.com",
		GIT_COMMITTER_NAME: "test",
		GIT_COMMITTER_EMAIL: "test@example.com",
		PATH: `${scratch}/stubs:${process.env.PATH}`,
	});
	await $`mkdir -p ${scratch}/stubs`;
	writeFileSync(
		`${scratch}/stubs/gh`,
		`#!/bin/sh\nprintf '%s\\n' "$@" >> ${ghCalls}\necho https://github.com/owner/repo/pull/1\n`,
	);
	chmodSync(`${scratch}/stubs/gh`, 0o755);
	await $`git init --quiet --bare -b main ${scratch}/origin.git`;
	await $`git clone --quiet ${scratch}/origin.git ${checkout}`;
	writeFileSync(`${checkout}/settings.json`, "base\n");
	await $`git -C ${checkout} add . && git -C ${checkout} commit --quiet -m base`;
	await $`git -C ${checkout} push --quiet origin main`;
	// The checkout sits on a feature branch with an unrelated commit and an
	// uncommitted edit: neither may reach the pull request.
	await $`git -C ${checkout} switch --quiet -c feature`;
	writeFileSync(`${checkout}/other.txt`, "feature\n");
	await $`git -C ${checkout} add . && git -C ${checkout} commit --quiet -m feature`;
	writeFileSync(`${checkout}/settings.json`, "uncommitted\n");
});
afterAll(() => rmSync(scratch, { recursive: true, force: true }));

describe("expected use", () => {
	test("the change is one commit on the base, pushed, with a pull request", async () => {
		const url = await openPullRequest({
			repo: checkout,
			branch: "setup/change",
			change: async (worktree) => {
				writeFileSync(`${worktree}/settings.json`, "changed\n");
				return { paths: ["settings.json"], title: "setup: change it", body: "because" };
			},
		});
		expect(url).toBe("https://github.com/owner/repo/pull/1");
		const pushed = await $`git -C ${scratch}/origin.git log --format=%s main..setup/change`.text();
		expect(pushed).toBe("setup: change it\n");
		const files = await $`git -C ${scratch}/origin.git ls-tree --name-only setup/change`.text();
		expect(files).toBe("settings.json\n");
		expect(readFileSync(ghCalls, "utf8")).toContain("--title\nsetup: change it\n--body\nbecause\n");
	});
	test("the checkout is left as it was, its uncommitted edit included", async () => {
		expect(readFileSync(`${checkout}/settings.json`, "utf8")).toBe("uncommitted\n");
		expect((await $`git -C ${checkout} branch --show-current`.text()).trim()).toBe("feature");
	});
	test("no worktree and no local branch are left behind", async () => {
		expect(existsSync(`${checkout}/.claude/worktrees/setup-change`)).toBe(false);
		expect(await $`git -C ${checkout} branch --list setup/change`.text()).toBe("");
	});
});

describe("bad input", () => {
	test("nothing to commit opens nothing and cleans up", async () => {
		const url = await openPullRequest({
			repo: checkout,
			branch: "setup/nothing",
			change: async () => undefined,
		});
		expect(url).toBeUndefined();
		expect(await $`git -C ${checkout} branch --list setup/nothing`.text()).toBe("");
		expect(await $`git -C ${scratch}/origin.git branch --list setup/nothing`.text()).toBe("");
	});
	test("a change that throws still cleans up, and the error reaches the caller", async () => {
		const failing = openPullRequest({
			repo: checkout,
			branch: "setup/broken",
			change: async () => {
				throw new Error("broken change");
			},
		});
		expect(failing).rejects.toThrow("broken change");
		await failing.catch(() => undefined);
		expect(existsSync(`${checkout}/.claude/worktrees/setup-broken`)).toBe(false);
	});
});
