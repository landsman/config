// A throwaway git worktree for the scripts under bin/, so a script changes a
// repo without touching its checkout: cut from the freshly fetched base branch,
// under .claude/worktrees/ where the worktrees rule expects them, and removed
// with its local branch afterwards, whatever happened inside.
import { $ } from "bun";
import { defaultBranch, fetch } from "@lib/git/remote";

/** Runs `work` inside a new worktree on a new branch, and returns what it returns. */
export async function withWorktree<Result>(
	request: WorktreeRequest,
	work: (worktree: Worktree) => Promise<Result>,
): Promise<Result> {
	const { repo, branch } = request;
	const base = request.base ?? (await defaultBranch(repo));
	const path = `${repo}/.claude/worktrees/${branch.replaceAll("/", "-")}`;
	await fetch(repo, base);
	await $`git -C ${repo} worktree add --quiet -b ${branch} ${path} origin/${base}`;
	try {
		return await work({ path, branch, base });
	} finally {
		await $`git -C ${repo} worktree remove --force ${path}`.quiet().nothrow();
		await $`git -C ${repo} branch -D ${branch}`.quiet().nothrow();
	}
}

export type WorktreeRequest = {
	/** The checkout to branch off; it is only fetched, never switched or edited. */
	repo: string;
	branch: string;
	/** The branch on origin to start from; origin's default when left out. */
	base?: string;
};

export type Worktree = {
	path: string;
	branch: string;
	/** The base it was cut from, resolved. */
	base: string;
};
