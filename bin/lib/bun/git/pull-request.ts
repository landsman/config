// Proposes a change to a repo as a pull request without touching its checkout,
// for the scripts under bin/: a worktree from the fetched base branch, the
// change, one commit, a push and `gh pr create`. The worktree and the local
// branch are removed afterwards, whatever happened.
import { $ } from "bun";

/** Returns the pull request's URL, or undefined when `change` had nothing to commit. */
export async function openPullRequest(request: PullRequestRequest): Promise<string | undefined> {
	const { repo, branch, change, base = "main" } = request;
	const worktree = `${repo}/.claude/worktrees/${branch.replaceAll("/", "-")}`;
	await $`git -C ${repo} fetch --quiet origin ${base}`;
	await $`git -C ${repo} worktree add --quiet -b ${branch} ${worktree} origin/${base}`;
	try {
		const commit = await change(worktree);
		if (!commit) {
			return undefined;
		}
		await $`git -C ${worktree} add -- ${commit.paths}`;
		await $`git -C ${worktree} commit --quiet -m ${commit.title} -m ${commit.body}`;
		await $`git -C ${worktree} push --quiet -u origin ${branch}`;
		const created =
			await $`gh pr create --base ${base} --head ${branch} --title ${commit.title} --body ${commit.body}`
				.cwd(worktree)
				.text();
		return created.trim().split("\n").at(-1);
	} finally {
		await $`git -C ${repo} worktree remove --force ${worktree}`.quiet().nothrow();
		await $`git -C ${repo} branch -D ${branch}`.quiet().nothrow();
	}
}

export type PullRequestRequest = {
	/** The checkout to branch off; it is only fetched, never switched or edited. */
	repo: string;
	branch: string;
	base?: string;
	/** Edits files inside the worktree it is given, and says what to commit, or
	 *  undefined for nothing to do. */
	change: (worktree: string) => Promise<Commit | undefined>;
};

export type Commit = {
	/** Relative to the repo's root. */
	paths: string[];
	/** The commit subject and the PR title alike. */
	title: string;
	/** The commit body and the PR body alike. */
	body: string;
};
