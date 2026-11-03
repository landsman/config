// What commit-convention.ts would get wrong silently: letting a capitalised or
// untyped subject through, or refusing git's own subjects and a Forgejo draft.
import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { subjectProblem, titleProblem } from "@bin/git/commit-convention";

const script = join(import.meta.dir, "commit-convention.ts");
const directory = mkdtempSync(join(tmpdir(), "commit-convention-"));
afterAll(() => rmSync(directory, { recursive: true }));

describe("expected use", () => {
	test.each([
		"setup(agents): show the brain index at every session start",
		"deps: bump GHCR mirror to 1.173.0",
		"be(api)!: drop the v1 checkout endpoint",
		"ci(pollos): watch the terraform providers, nothing tracked them",
		`docs: ${"a".repeat(94)}`,
	])("passes %s", (subject) => {
		expect(subjectProblem(subject)).toBeUndefined();
	});

	test.each([
		"Merge branch 'main' into feature",
		'Revert "setup: install glab"',
		"fixup! setup: install glab",
		"squash! setup: install glab",
		"",
	])("lets git's own %p through", (subject) => {
		expect(subjectProblem(subject)).toBeUndefined();
	});

	test("a PR title drops Forgejo's draft marker, a commit subject does not", () => {
		expect(titleProblem("WIP: setup: install glab")).toBeUndefined();
		expect(subjectProblem("WIP: setup: install glab")).toMatch(/prefix/);
	});

	test("the hook reads the first line that is not a comment", async () => {
		const message = join(directory, "COMMIT_EDITMSG");
		writeFileSync(message, "# a comment\nsetup: install glab\n\nbody\n");
		const run = Bun.spawnSync([process.execPath, script, message]);
		expect(run.exitCode).toBe(0);
	});
});

describe("bad input", () => {
	test.each([
		["Stripe payments: local setup", /prefix/],
		["add the thing", /prefix/],
		["feat: add the thing", /`feat` is not one of the types/],
		["be(auth): User extends SoftDeletableEntity", /lowercase letter/],
		["Setup: install glab", /prefix/],
		["setup(Agents): install glab", /prefix/],
		["setup:install glab", /prefix/],
		["setup: install glab.", /full stop/],
		[`docs: ${"a".repeat(95)}`, /101 characters/],
	])("refuses %p", (subject, problem) => {
		expect(subjectProblem(subject)).toMatch(problem);
	});

	test("a refused title exits 1 and says what it got and what is expected", () => {
		const run = Bun.spawnSync([process.execPath, script, "--title", "Fix bug"]);
		expect(run.exitCode).toBe(1);
		const said = run.stderr.toString();
		expect(said).toContain("got:      Fix bug");
		expect(said).toContain("types:    security deps ci");
	});

	test("a missing title is refused, not taken as an empty subject", () => {
		expect(titleProblem("WIP: ")).toMatch(/empty/);
		const run = Bun.spawnSync([process.execPath, script, "--title"]);
		expect(run.exitCode).toBe(1);
	});
});
