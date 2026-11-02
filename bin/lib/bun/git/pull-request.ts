// Proposes a change to a repo as a pull request without touching its checkout,
// for the scripts under bin/: the change in a throwaway worktree off the base
// branch, one commit, a push and `gh pr create`.
import { $ } from "bun";
import { commit, type Commit } from "@lib/git/commit";
import { push } from "@lib/git/remote";
import { withWorktree, type WorktreeRequest } from "@lib/git/worktree";

/** Returns the pull request's URL, or undefined when `change` had nothing to commit. */
export async function openPullRequest(request: PullRequestRequest): Promise<string | undefined> {
	return withWorktree(request, async (worktree) => {
		const proposed = await request.change(worktree.path);
		if (!proposed) {
			return undefined;
		}
		await commit(worktree.path, proposed);
		await push(worktree.path, worktree.branch);
		const created =
			await $`gh pr create --base ${worktree.base} --head ${worktree.branch} --title ${proposed.title} --body ${proposed.body}`
				.cwd(worktree.path)
				.text();
		return created.trim().split("\n").at(-1);
	});
}

export type PullRequestRequest = WorktreeRequest & {
	/** Edits files inside the worktree it is given, and says what to commit, or
	 *  undefined for nothing to do. */
	change: (worktree: string) => Promise<Commit | undefined>;
};
