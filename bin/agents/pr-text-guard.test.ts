// What pr-text-guard.ts would get wrong silently: letting a bad title through
// because it sat in a flag form it did not read, or holding a Bash call that
// opens no pull request. Run with no git config at all, so forbidden-names has
// no list and only its email check can refuse.
import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pullRequestText } from "@bin/agents/pr-text-guard";
import { runHook } from "@lib/testing";

const hook = join(import.meta.dir, "pr-text-guard.ts");
const home = mkdtempSync(join(tmpdir(), "pr-text-guard-"));
afterAll(() => rmSync(home, { recursive: true }));
const isolated = { HOME: home, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" };

/** The hook's refusal for this call, or undefined when it lets it through. */
async function refusal(event: object): Promise<string | undefined> {
	const answer = await runHook(hook, { cwd: home, ...event }, isolated);
	return answer?.hookSpecificOutput?.permissionDecisionReason;
}

const bash = (command: string) => ({ tool_name: "Bash", tool_input: { command } });

describe("expected use", () => {
	test("a good title and body pass, on gh, glab and the Forgejo MCP", async () => {
		expect(
			await refusal(bash('gh pr create --title "setup: install glab" --body "why"')),
		).toBeUndefined();
		expect(await refusal(bash("glab mr create -t 'setup: install glab' -d why"))).toBeUndefined();
		expect(
			await refusal({
				tool_name: "mcp__forgejo__create_pull_request",
				tool_input: { title: "WIP: setup: install glab", body: "why" },
			}),
		).toBeUndefined();
	});

	test("a capitalised title is refused with the validator's own message", async () => {
		const said = await refusal(bash('gh pr create --title "Install glab" --body "why"'));
		expect(said).toContain("got:      Install glab");
	});

	test("an email address in the title is refused by forbidden-names", async () => {
		const said = await refusal({
			tool_name: "mcp__forgejo__update_pull_request",
			tool_input: { title: "setup: commit as someone@example.com", body: "" },
		});
		expect(said).toContain("forbidden-names: an email address");
	});

	test.each([
		['gh pr create --title "setup: a" --body x', "setup: a"],
		["gh pr create -t 'setup: a' -b x", "setup: a"],
		["gh pr edit 3 --title=setup:a", "setup:a"],
		['gh pr create --title "setup: say \\"hi\\""', 'setup: say "hi"'],
	])("reads the title out of %s", (command, title) => {
		expect(pullRequestText("Bash", { command })?.title).toBe(title);
	});

	test("a body file is read as the body", () => {
		const file = join(home, "body.md");
		writeFileSync(file, "the body\n");
		expect(
			pullRequestText("Bash", { command: `gh pr create -t 'setup: a' -F ${file}` })?.body,
		).toContain("the body");
	});
});

describe("bad input", () => {
	test("a command that opens no pull request is not held", async () => {
		expect(await refusal(bash("git commit -m 'Whatever.'"))).toBeUndefined();
		expect(pullRequestText("Bash", { command: "gh pr view 3" })).toBeUndefined();
	});

	test("a title that is not a literal is left alone, not refused", () => {
		expect(
			pullRequestText("Bash", { command: 'gh pr create --title "$TITLE"' })?.title,
		).toBeUndefined();
		expect(pullRequestText("Bash", { command: "gh pr create --fill" })?.title).toBeUndefined();
	});

	test("an update that sets no title checks only the body", async () => {
		expect(
			await refusal({
				tool_name: "mcp__forgejo__update_pull_request",
				tool_input: { body: "why" },
			}),
		).toBeUndefined();
	});

	test("no event at all says nothing", async () => {
		const proc = Bun.spawnSync([process.execPath, hook], { stdin: new Blob(["not json"]) });
		expect(proc.exitCode).toBe(0);
		expect(proc.stdout.toString()).toBe("");
	});
});
