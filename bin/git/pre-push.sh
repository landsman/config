#!/usr/bin/env bash
# Run the repo's own checks before a push leaves the machine.
#
#   pre-push.sh <remote> <url>   as the pre-push hook in .gitconfig, refs on stdin
#
# A repo opts in by giving its Makefile a `pre-push` target; one without it is
# pushed unchecked, so this costs nothing in a repo that never asked. CI then
# confirms a green run instead of being where a change is tried first.
#
# ponytail: checks the working tree, not the pushed commit, so an uncommitted
# fix can hide a broken commit. A `git worktree add` of the pushed sha would
# close that, at the price of a fresh checkout on every push.
set -euo pipefail

# Only deletions (every local sha all zeros): nothing new to check.
pushed=0
while read -r _ local_sha _ _; do
	[ -z "${local_sha//0/}" ] || pushed=1
done
[ "$pushed" = 1 ] || exit 0

root=$(git rev-parse --show-toplevel)
grep -q '^pre-push:' "$root/Makefile" 2>/dev/null || exit 0

echo "pre-push: make pre-push (skip with git push --no-verify)" >&2
make -C "$root" pre-push >&2
