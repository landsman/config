// For the tests of the git helpers: real git against a local bare origin, in a
// throwaway folder, with this machine's git config shut out.
import { $ } from "bun";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { isolateGitConfig } from "@lib/git/testing/config";

/** A bare `origin` whose `main` holds the given files, and `checkout`, a clone
 *  of it. Call `remove()` in afterAll. */
export async function gitSandbox(files: Record<string, string> = { "settings.json": "base\n" }) {
	isolateGitConfig();
	const scratch = mkdtempSync(`${tmpdir()}/git-sandbox-`);
	const origin = `${scratch}/origin.git`;
	const checkout = `${scratch}/checkout`;
	await $`git init --quiet --bare -b main ${origin}`;
	await $`git clone --quiet ${origin} ${checkout}`;
	for (const [name, content] of Object.entries(files)) {
		writeFileSync(`${checkout}/${name}`, content);
	}
	await $`git -C ${checkout} add . && git -C ${checkout} commit --quiet -m base`;
	await $`git -C ${checkout} push --quiet origin main`;
	return {
		scratch,
		origin,
		checkout,
		remove: () => rmSync(scratch, { recursive: true, force: true }),
	};
}
