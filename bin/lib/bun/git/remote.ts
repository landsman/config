// Talking to `origin`, for the scripts under bin/. Plain git, no forge CLI, so
// it answers the same for GitHub, Forgejo and a local bare repo in a test.
import { $ } from "bun";

/** The branch origin's HEAD points at — `main` here, but read, not assumed. */
export async function defaultBranch(repo: string) {
	const answer = await $`git -C ${repo} ls-remote --symref origin HEAD`.text();
	const branch = answer.match(/^ref: refs\/heads\/(\S+)\s+HEAD$/m)?.[1];
	if (!branch) throw new Error(`origin of ${repo} names no default branch`);
	return branch;
}

export async function fetch(repo: string, branch: string) {
	await $`git -C ${repo} fetch --quiet origin ${branch}`;
}

/** Pushes the branch to origin and tracks it there. */
export async function push(repo: string, branch: string) {
	await $`git -C ${repo} push --quiet -u origin ${branch}`;
}
