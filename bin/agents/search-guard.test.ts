// What search-guard.ts would get wrong silently: letting a sweep of the disk or of
// ~/projects through, or refusing an ordinary search: a grep pattern that looks like a
// path, a named folder outside the project, a plain read of one file.
import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import { runHook } from "@lib/testing";

const hook = join(import.meta.dir, "search-guard.ts");

const refused = async (toolName: string, toolInput: object) =>
	(await runHook(hook, { tool_name: toolName, tool_input: toolInput }))?.hookSpecificOutput
		?.permissionDecision === "deny";
const bash = (command: string) => refused("Bash", { command });

describe("expected use", () => {
	test.each([
		"find . -name '*.kt'",
		"find src -path '*/main/*' -type f",
		`grep -rn "/api/v1" src`,
		"grep foo /etc/hosts",
		"grep -rn foo /etc",
		"ls; find /usr -name a",
		"rg foo",
		"rg -n '/Users/x' src",
		"rg foo ~/projects/landsman/homelab",
		"grep -rn hook ~/.claude",
		"grep -ril term ~/projects/landsman/brain/wiki",
		"fd banks.csv",
		"find /tmp/x -name y",
		"ls /",
		"git grep foo",
		"mdfind -onlyin . banks.csv",
		'git commit -m "docs: say how to locate the brain"',
		'echo "find / -name banks.csv swept the disk" > body.md',
		"gh pr create --body \"$(cat <<'EOF'\nOnce `find / -name x` ran, mdfind too.\nEOF\n)\"",
		'git commit -m "refuse a sweep (find / once swept the disk)"',
		'git commit -m "this time find / is refused"',
		'gh pr edit --body "a tree walk (find, fd, rg) that names `~/projects` / `~/Library`"',
		'gh pr edit --body "| find | / |"',
	])("lets %s through", async (command) => {
		expect(await bash(command)).toBe(false);
	});

	test("lets the Glob and Grep tools search a named folder", async () => {
		expect(await refused("Glob", { pattern: "**/*.kt" })).toBe(false);
		expect(await refused("Grep", { pattern: "x", path: `${process.env.HOME}/.claude` })).toBe(
			false,
		);
	});
});

describe("bad input", () => {
	test.each([
		"find / -name banks.csv 2>/dev/null | head -1",
		"find ~ -name banks.csv",
		'find "$HOME" -name x',
		"find ~/projects -maxdepth 2",
		"find ~/projects/ -name x",
		"echo $(find / -name x)",
		"grep -Rl foo ~/projects",
		"rg foo ~",
		"fd banks.csv /",
		"du -sh ~/Library",
		"ls -R /",
		"sudo find /Users/someone -name x",
		"mdfind banks.csv",
		"locate banks.csv",
		"grep -n -r foo ~",
		"grep --recursive foo ~",
		"xargs find / -name x",
		"cd src\nfind / -name x",
		"du -sh ~/projects/*",
		"find ~/projects/* -maxdepth 1 -name x",
		'find "$HOME"/projects -name x',
	])("refuses %s", async (command) => {
		expect(await bash(command)).toBe(true);
	});

	test("refuses the Glob and Grep tools at the disk or home root", async () => {
		expect(await refused("Glob", { pattern: "**/banks.csv", path: "/" })).toBe(true);
		expect(await refused("Grep", { pattern: "x", path: process.env.HOME })).toBe(true);
	});
});
