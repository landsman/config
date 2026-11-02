// What commit would get wrong silently: another changed file riding along, or
// a staged one it was not asked to commit.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { $ } from "bun";
import { writeFileSync } from "node:fs";
import { commit } from "@lib/git/commit";
import { gitSandbox } from "@lib/git/testing/sandbox";

let sandbox: Awaited<ReturnType<typeof gitSandbox>>;
beforeAll(async () => {
	sandbox = await gitSandbox({ "settings.json": "base\n", "other.txt": "base\n" });
});
afterAll(() => sandbox.remove());

describe("expected use", () => {
	test("only the named paths are committed, with the title and body", async () => {
		const repo = sandbox.checkout;
		writeFileSync(`${repo}/settings.json`, "changed\n");
		writeFileSync(`${repo}/other.txt`, "changed\n");
		writeFileSync(`${repo}/staged.txt`, "staged\n");
		await $`git -C ${repo} add staged.txt`;
		await commit(repo, { paths: ["settings.json"], title: "setup: change it", body: "because" });
		expect((await $`git -C ${repo} log -1 --format=%B`.text()).trim()).toBe(
			"setup: change it\n\nbecause",
		);
		expect(await $`git -C ${repo} show --name-only --format= HEAD`.text()).toBe("settings.json\n");
		expect(await $`git -C ${repo} status --porcelain`.text()).toBe(" M other.txt\nA  staged.txt\n");
	});
});

describe("bad input", () => {
	test("a path with no change fails instead of an empty commit", async () => {
		const empty = commit(sandbox.checkout, {
			paths: ["settings.json"],
			title: "setup: nothing",
			body: "",
		});
		await expect(empty).rejects.toThrow();
	});
});
