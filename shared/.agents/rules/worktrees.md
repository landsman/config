# Worktrees

**Work that changes a repo happens in a git worktree, not in my checkout** —
unless I say to do it somewhere else for that task.

The checkout is where I am working. It may hold uncommitted changes, a branch I
have half-finished, or a server running off it, and another agent may be in it
at the same time. An agent that switches its branch, stashes or edits there
collides with whatever else is going on, and the collision surfaces as my work
disappearing, not as an error.

- **Start from the target branch**, fetched: `origin/main`, not whatever the
  checkout happens to be on. A branch cut from someone's feature branch drags
  their commits into the PR.
- **Use the harness's own worktree support** when it has one — Claude Code's
  puts them under `.claude/worktrees/`. Without it, `git worktree add` into that
  same folder, so every agent's worktrees sit where
  [where the repos live](where-repos-live.md) already says to expect them.
- **Leave it when the work is pushed**; removing it is `git worktree remove`,
  and only once nothing in it is unpushed.

Reading, searching and answering a question need no worktree — the rule is about
writing. "Do it here", "on this branch" or "in my checkout" is the exception,
and it holds for that task only.
