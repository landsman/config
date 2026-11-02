// One commit of named paths, for the scripts under bin/. Only those paths go
// in, so nothing else left changed in the tree rides along.
import { $ } from "bun";

export async function commit(repo: string, change: Commit) {
	await $`git -C ${repo} add -- ${change.paths}`;
	await $`git -C ${repo} commit --quiet -m ${change.title} -m ${change.body} -- ${change.paths}`;
}

export type Commit = {
	/** Relative to the repo's root. */
	paths: string[];
	/** The commit subject, and the PR title when one is opened from it. */
	title: string;
	/** The commit body, and the PR body when one is opened from it. */
	body: string;
};
