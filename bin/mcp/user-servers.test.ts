// Self-check for ./user-servers.ts. What it would get wrong silently: re-adding
// a server that is already right, which signs it out, or keeping one whose
// entry changed.
import { afterAll, describe, expect, test } from "bun:test";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Action, plan, serversIn } from "@bin/mcp/user-servers";

const cloudflare = { type: "http", url: "https://mcp.cloudflare.com/mcp" };
const wanted = { cloudflare };
const sandbox = mkdtempSync(join(tmpdir(), "user-servers-"));
afterAll(() => rmSync(sandbox, { recursive: true, force: true }));

describe("expected use", () => {
	test("a server registered as written is kept, whatever its key order", () => {
		const registered = { cloudflare: { url: cloudflare.url, type: "http" } };
		expect(plan(wanted, registered).map((step) => step.action)).toEqual([Action.Keep]);
	});
	test("a token in the registered env does not make it look changed", () => {
		const registered = { cloudflare: { ...cloudflare, env: { TOKEN: "secret" } } };
		expect(plan(wanted, registered).map((step) => step.action)).toEqual([Action.Keep]);
	});
	test("a server whose URL changed is replaced", () => {
		const registered = { cloudflare: { ...cloudflare, url: "https://old.example/mcp" } };
		expect(plan(wanted, registered).map((step) => step.action)).toEqual([Action.Replace]);
	});
	test("a missing server is added, and someone else's is left alone", () => {
		const registered = { pencil: { type: "stdio", command: "pencil" } };
		expect(plan(wanted, registered)).toEqual([
			{ action: Action.Add, name: "cloudflare", server: cloudflare },
		]);
	});
	test("install runs no claude command for a kept server", async () => {
		const calls = await install({ mcpServers: { cloudflare } });
		expect(calls).toEqual([]);
	});
	test("install removes a changed server before adding it again", async () => {
		const calls = await install({
			mcpServers: { cloudflare: { ...cloudflare, url: "https://old.example/mcp" } },
		});
		expect(calls).toEqual([
			"mcp remove cloudflare -s user",
			`mcp add-json -s user cloudflare ${JSON.stringify(cloudflare)}`,
		]);
	});
	test("the tracked list is readable", () => {
		expect(
			Object.keys(
				serversIn(
					join(import.meta.dir, "../../shared/.agents/skills/mcp-servers/user-servers.json"),
				),
			),
		).toContain("cloudflare");
	});
});

describe("bad input", () => {
	test("a broken ~/.claude.json throws instead of reading as nothing registered", () => {
		const broken = join(sandbox, "broken.json");
		writeFileSync(broken, "{ not json");
		expect(() => serversIn(broken)).toThrow(/not readable JSON/);
	});
	test("mcpServers that is not an object throws", () => {
		const odd = join(sandbox, "odd.json");
		writeFileSync(odd, JSON.stringify({ mcpServers: ["cloudflare"] }));
		expect(() => serversIn(odd)).toThrow(/not an object/);
	});
	test("a config with no mcpServers at all means nothing registered", () => {
		const empty = join(sandbox, "empty.json");
		writeFileSync(empty, "{}");
		expect(plan(wanted, serversIn(empty)).map((step) => step.action)).toEqual([Action.Add]);
	});
	test("no ~/.claude.json at all means add", async () => {
		const calls = await install(undefined);
		expect(calls).toEqual([`mcp add-json -s user cloudflare ${JSON.stringify(cloudflare)}`]);
	});
});

/** Runs the script's install against a stub `claude` that records its arguments,
 *  and a fake ~/.claude.json (none when `claudeJson` is undefined). */
async function install(claudeJson: object | undefined): Promise<string[]> {
	const run = mkdtempSync(join(sandbox, "run-"));
	const callsFile = join(run, "calls");
	const stub = join(run, "claude");
	writeFileSync(stub, `#!/bin/sh\necho "$*" >> "${callsFile}"\n`);
	chmodSync(stub, 0o755);
	const configFile = join(run, ".claude.json");
	if (claudeJson !== undefined) writeFileSync(configFile, JSON.stringify(claudeJson));
	const result = Bun.spawnSync(["bun", join(import.meta.dir, "user-servers.ts"), "install"], {
		env: { ...process.env, PATH: `${run}:${process.env.PATH}`, CLAUDE_JSON: configFile },
	});
	expect(result.exitCode).toBe(0);
	try {
		// Only cloudflare's calls: the rest of the tracked list is added too, and the
		// cases here are about one server.
		return readFileSync(callsFile, "utf8")
			.trim()
			.split("\n")
			.filter((call) => call.split(" ").includes("cloudflare"));
	} catch {
		return [];
	}
}
