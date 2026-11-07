// What search-guard.ts would get wrong silently: letting a sweep of the disk or of
// ~/projects through, or refusing an ordinary search inside the project — a grep
// pattern that looks like a path, a find pattern, a plain read of one file.
import { afterAll, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runHook } from "@lib/testing";

const hook = join(import.meta.dir, "search-guard.ts");
// Under the home folder, not the temp dir, which the hook allows on its own.
const project = mkdtempSync(join(process.env.HOME ?? "", ".search-guard-test-"));
mkdirSync(join(project, "src"));
afterAll(() => rmSync(project, { recursive: true }));

const run = (tool_name: string, tool_input: object) =>
	runHook(hook, { cwd: project, tool_name, tool_input }, { CLAUDE_PROJECT_DIR: project });
const refused = async (tool_name: string, tool_input: object) =>
	(await run(tool_name, tool_input))?.hookSpecificOutput?.permissionDecision === "deny";
const bash = (command: string) => refused("Bash", { command });

test.each([
	"find / -name banks.csv 2>/dev/null | head -1",
	"find ~ -name banks.csv",
	"find ~/projects -maxdepth 2",
	"cd / && find . -name x",
	"ls; find /usr -name a",
	"echo $(find / -name x)",
	"grep -rn foo /etc",
	"grep -Rl foo ~/projects",
	"rg foo ~",
	"rg -e foo /usr",
	"fd banks.csv /",
	"du -sh ~/Library",
	"ls -R /",
	"sudo find /var -name x",
	"mdfind banks.csv",
	"locate banks.csv",
	"cd .. && rg foo",
])("refuses %s", async (command) => {
	expect(await bash(command)).toBe(true);
});

test.each([
	"find . -name '*.kt'",
	"find src -path '*/main/*' -type f",
	`grep -rn "/api/v1" src`,
	"grep foo /etc/hosts",
	"rg foo",
	"rg -n '/Users/x' src",
	"fd banks.csv",
	"find /tmp/x -name y",
	`find ${project}/src`,
	"ls /",
	"git grep foo",
	"cd src && find . -name x",
	"grep -ril term ~/projects/landsman/brain/wiki",
	"mdfind -onlyin . banks.csv",
])("lets %s through", async (command) => {
	expect(await bash(command)).toBe(false);
});

test("refuses the Glob and Grep tools outside the project", async () => {
	expect(await refused("Glob", { pattern: "**/banks.csv", path: "/" })).toBe(true);
	expect(await refused("Grep", { pattern: "x", path: process.env.HOME })).toBe(true);
});

test("lets the Glob and Grep tools search the project", async () => {
	expect(await refused("Glob", { pattern: "**/*.kt" })).toBe(false);
	expect(await refused("Grep", { pattern: "x", path: join(project, "src") })).toBe(false);
});
