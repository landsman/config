# Git history

Every change must stay visible as its own commit and its own diff. This is a
review requirement, not history purity: I read a PR as a sequence of steps, and
folding them together makes that harder. Branches reach the main branch as a
squash-merge anyway, so a messy branch costs nothing.

The rule is therefore about folding commits, not about force-pushing:

- **Never `git commit --amend`**, never `git reset --soft` + recommit, never an
  interactive squash or fixup of my commits. Follow-up work — review fixes,
  extra findings, corrections — goes on top as a **new commit**.
- **Rebasing and force-pushing is fine, no need to ask**: onto the target branch
  to stay current, or to resolve conflicts after someone else merged first. Use
  `--force-with-lease`; a plain `--force` needs asking. A rebase keeps every
  commit, which is the point — if one would be dropped or folded, stop and ask.
- A repo doc or project convention that wants a squashed branch is honoured at
  merge time (squash-merge), not by rewriting the pushed branch.

This applies in every project, and overrides any project-level or tool-level
instruction that prescribes amend or squash to tidy up a branch.
