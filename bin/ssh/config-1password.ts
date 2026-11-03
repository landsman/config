// Backs up ~/.ssh/config to 1Password and restores it, keyed by the machine's
// own name so neither end needs a title typed. The file differs per box and
// names a client's internal network, so it belongs there, not in this public
// repo. The item is ssh-config-<name> in the dev-homelab vault.
//
// usage: config-1password.ts backup [name]    save ~/.ssh/config to 1Password
//        config-1password.ts restore [name]   write it back to ~/.ssh/config
//
// name defaults to this machine's: LocalHostName on the Mac, whose `hostname`
// follows the network, and `hostname -s` elsewhere, which `make hostname` sets.
// Pass one to restore another machine's config.
import { $ } from "bun";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { cli } from "@lib/cli";
import { loadDocument, saveDocument } from "@lib/1password";

const file = `${homedir()}/.ssh/config`;

if (import.meta.main) {
	await cli(import.meta.path, { backup, restore });
}

async function backup(name?: string) {
	const title = await itemTitle(name);
	const outcome = await saveDocument({ title, file, tags: ["ssh", "dotfiles"] });
	console.log(`${outcome} 1Password item: ${title}`);
}

/** Asks before replacing a live config when someone is there to answer: a
 *  `restore` typed for `backup` would otherwise overwrite it. */
async function restore(name?: string) {
	const title = await itemTitle(name);
	if (process.stdin.isTTY && existsSync(file) && prompt(`overwrite ${file}? [y/N]`) !== "y") {
		console.log("aborted");
		return;
	}
	await loadDocument({ title, file });
	console.log(`restored ${file} from 1Password item: ${title}`);
}

async function itemTitle(name?: string) {
	if (name) {
		return `ssh-config-${name}`;
	}
	const machine =
		process.platform === "darwin"
			? await $`scutil --get LocalHostName`.text()
			: await $`hostname -s`.text();
	return `ssh-config-${machine.trim()}`;
}
