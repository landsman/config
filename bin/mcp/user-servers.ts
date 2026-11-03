#!/usr/bin/env bun
// Registers the servers in user-servers.json, beside this script, at Claude
// Code's user scope, so /mcp lists them under User MCPs rather than among the
// forty plugin servers.
//
// usage:
//   user-servers.ts install   register what is missing or changed, keep the rest
//   user-servers.ts plan      print `<action> <name>` per server, change nothing
//
// A server already registered as written is kept, so a rerun does not drop its
// OAuth sign-in. CLAUDE_JSON overrides ~/.claude.json, for the test.
import { $ } from "bun";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { isDeepStrictEqual } from "node:util";
import { match } from "ts-pattern";
import { cli } from "@lib/cli";

const wantedFile = join(import.meta.dir, "user-servers.json");

async function install() {
	for (const step of currentPlan()) {
		await match(step.action)
			.with(Action.Keep, async () => {})
			.with(Action.Add, async () => {
				await addServer(step);
			})
			.with(Action.Replace, async () => {
				await $`claude mcp remove ${step.name} -s user`.quiet();
				await addServer(step);
			})
			.exhaustive();
		console.log(`${step.action} ${step.name}`);
	}
}

async function addServer(step: Step) {
	await $`claude mcp add-json -s user ${step.name} ${JSON.stringify(step.server)}`.quiet();
}

function currentPlan(): Step[] {
	const claudeJson = process.env.CLAUDE_JSON ?? join(homedir(), ".claude.json");
	return plan(serversIn(wantedFile), existsSync(claudeJson) ? serversIn(claudeJson) : {});
}

export enum Action {
	Keep = "keep",
	Add = "add",
	Replace = "replace",
}

type Servers = Record<string, object>;

export type Step = { action: Action; name: string; server: object };

/** What to do with each wanted server, given what is registered now. The
 *  registered entry's `env` is left out of the comparison: that is where a
 *  token sits, and it is never in the tracked file. */
export function plan(wanted: Servers, registered: Servers): Step[] {
	return Object.entries(wanted).map(([name, server]) => {
		const current = registered[name];
		if (current === undefined) return { action: Action.Add, name, server };
		const { env: _env, ...withoutEnv } = current as { env?: unknown };
		const same = isDeepStrictEqual(sortedKeys(withoutEnv), sortedKeys(server));
		return { action: same ? Action.Keep : Action.Replace, name, server };
	});
}

/** The `mcpServers` of a Claude config, or of the tracked list. A file that is
 *  not JSON throws with its path, rather than reading as "nothing registered"
 *  and re-adding every server over a sign-in. */
export function serversIn(file: string): Servers {
	let parsed: unknown;
	try {
		parsed = JSON.parse(readFileSync(file, "utf8"));
	} catch (error) {
		throw new Error(`${file} is not readable JSON: ${(error as Error).message}`);
	}
	const servers = (parsed as { mcpServers?: unknown } | null)?.mcpServers ?? {};
	if (typeof servers !== "object" || servers === null || Array.isArray(servers)) {
		throw new Error(`${file}: mcpServers is not an object`);
	}
	return servers as Servers;
}

/** Key order is not meaning: Claude Code writes `url` before `type`. */
function sortedKeys(value: object): object {
	return Object.fromEntries(
		Object.entries(value).sort(([left], [right]) => left.localeCompare(right)),
	);
}

// Last, not first: it runs during module load, and the enum above has to exist by then.
if (import.meta.main) {
	await cli(import.meta.path, {
		install: () => install(),
		plan: async () => {
			for (const step of currentPlan()) console.log(`${step.action} ${step.name}`);
		},
	});
}
