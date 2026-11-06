// Backs up the files that differ per machine and stay out of this public repo
// to 1Password, and restores them, keyed by the machine's own name so neither
// end needs a title typed. Each is the item <file>-<machine> in the dev-homelab
// vault; a file this machine does not have is skipped, both ways.
//
// usage: machine-files.ts backup [machine]    save this machine's files to 1Password
//        machine-files.ts restore [machine]   write them back from there
//
// machine defaults to this one: LocalHostName on the Mac, whose `hostname`
// follows the network, and `hostname -s` elsewhere, which `make hostname` sets.
// Pass one to restore another machine's files.
import { $ } from "bun";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { cli } from "@lib/cli";
import { loadDocument, saveDocument } from "@lib/1password";

/** Why each is not stowed: it names a client, and it differs per machine. */
const machineFiles = [
	// Host blocks for a client's internal network.
	{ name: "ssh-config", path: `${homedir()}/.ssh/config`, tags: ["ssh"] },
	// The Claude Code settings that must not reach this repo, see the
	// everything-as-code rule.
	{
		name: "claude-settings-local",
		path: `${homedir()}/.claude/settings.local.json`,
		tags: ["claude"],
	},
];

if (import.meta.main) {
	await cli(import.meta.path, { backup, restore });
}

async function backup(machine?: string) {
	const suffix = machine ?? (await machineName());
	for (const file of machineFiles) {
		const title = `${file.name}-${suffix}`;
		if (!existsSync(file.path)) {
			console.log(`skipped ${title}: no ${file.path} here`);
			continue;
		}
		const outcome = await saveDocument({
			title,
			file: file.path,
			tags: [...file.tags, "dotfiles"],
		});
		console.log(`${outcome} ${title}`);
	}
}

/** Asks before replacing a live file when someone is there to answer: a
 *  `restore` typed for `backup` would otherwise overwrite it. */
async function restore(machine?: string) {
	const suffix = machine ?? (await machineName());
	for (const file of machineFiles) {
		const title = `${file.name}-${suffix}`;
		if (
			process.stdin.isTTY &&
			existsSync(file.path) &&
			prompt(`overwrite ${file.path}? [y/N]`) !== "y"
		) {
			console.log(`kept ${file.path}`);
			continue;
		}
		const outcome = await loadDocument({ title, file: file.path });
		console.log(
			outcome === "loaded"
				? `restored ${file.path} from ${title}`
				: `skipped ${title}: not in 1Password`,
		);
	}
}

async function machineName() {
	const name =
		process.platform === "darwin"
			? await $`scutil --get LocalHostName`.text()
			: await $`hostname -s`.text();
	return name.trim();
}
