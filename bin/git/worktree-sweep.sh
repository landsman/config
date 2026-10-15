#!/usr/bin/env bash
# Remove the agent worktrees of a repo whose work is finished.
#
#   worktree-sweep.sh <dir>          in the repo <dir> belongs to
#   worktree-sweep.sh --list <dir>   say what would go, remove nothing
#   worktree-sweep.sh --hook <args>  as the post-checkout hook in .gitconfig
#
# As a hook it runs on every `git worktree add`, so the next worktree an agent
# makes clears out the old ones, whichever harness made them. Neither harness
# can be left to do it at exit: Claude Code offers it only for a worktree it
# made itself (EnterWorktree, --worktree), never for one an agent made with
# `git worktree add`, and opencode has no exit event at all.
#
# Finished means all of these, and only under <main checkout>/.claude/worktrees/,
# where the worktrees rule puts them:
# - clean, submodules included: an uncommitted change exists nowhere else;
# - every commit is on a remote, or the branch's upstream is gone (merged and
#   deleted, and fetch.prune took the remote ref with it). The local branch
#   stays either way;
# - not locked, nothing in its git dir changed for a day, and no process of mine
#   has its working directory in it: a session paused on a pushed branch passes
#   the first two.
#
# ponytail: ignored files (a build, a copied .env) go with the worktree; they
# are rebuilt or recopied, so no check.
set -euo pipefail
unset CDPATH
# Inherited from the git command that runs the hook, these would answer for the
# wrong repo.
# shellcheck disable=SC2046 # git's own list of variable names, split on purpose
unset $(git rev-parse --local-env-vars)

if [ "${1-}" = --hook ]; then
	# post-checkout gets <old HEAD> <new HEAD> <flag>; the old one is all zeros
	# only for a new worktree or a clone. Its exit code becomes git's, so a
	# failed sweep must not fail the `git worktree add` that ran it.
	prev=${2-}
	[ -n "$prev" ] && [ -z "${prev//0/}" ] || exit 0
	"$0" "$PWD" >&2 || true
	exit 0
fi

list=
[ "${1-}" != --list ] || { list=1; shift; }
dir=${1:?usage: worktree-sweep.sh [--list] <dir> | --hook <old> <new> <flag>}
# The test's seam; a day otherwise.
idle=${WORKTREE_SWEEP_IDLE_MINUTES:-1440}

[ "$(git -C "$dir" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] || exit 0
git -C "$dir" worktree prune
main=$(git -C "$dir" worktree list --porcelain | sed -n '1s/^worktree //p')

# Something happened in the worktree whose git dir is $1 within $idle minutes.
recent() {
	local t
	[ -z "$(find "$1/HEAD" "$1/index" -mmin -"$idle" 2>/dev/null)" ] || return 0
	# The last entry's own time, not the file's: gc rewrites every reflog of the
	# repo at once, which made all of them look touched that morning.
	t=$(tail -n1 "$1/logs/HEAD" 2>/dev/null | cut -f1 | awk '{ print $(NF - 1) }')
	[ -n "$t" ] && [ $(($(date +%s) - t)) -lt $((idle * 60)) ]
}

shipped() {
	local branch
	[ -n "$(git -C "$1" rev-list -n1 HEAD --not --remotes)" ] || return 0
	branch=$(git -C "$1" symbolic-ref -q HEAD) || return 1
	[ "$(git -C "$1" for-each-ref --format='%(upstream:track)' "$branch")" = "[gone]" ]
}

# Cheapest first: status walks the whole tree, a third of a second in a big one.
finished() {
	local gd s
	gd=$(git -C "$1" rev-parse --path-format=absolute --git-dir 2>/dev/null) || return 1
	[ ! -e "$gd/locked" ] || return 1
	# Before status, which may rewrite the index and so reset the clock.
	! recent "$gd" || return 1
	shipped "$1" || return 1
	# The exit code first: a broken submodule gitfile fails with no output.
	s=$(git -C "$1" --no-optional-locks status --porcelain 2>/dev/null) && [ -z "$s" ] || return 1
	# A submodule's objects live in this worktree's git dir and go with it.
	s=$(git -C "$1" submodule foreach --quiet --recursive 'git rev-list -n1 HEAD --not --remotes' 2>/dev/null) &&
		[ -z "$s" ]
}

# Working directories of my processes: a dev server, a shell, an agent started there.
cwds() {
	if command -v lsof >/dev/null; then
		lsof -nP -a -u "$(id -u)" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'
	else
		for c in /proc/[0-9]*/cwd; do readlink "$c" 2>/dev/null || true; done
	fi
}

used=
git -C "$dir" worktree list --porcelain | sed -n 's/^worktree //p' | while IFS= read -r w; do
	case $w in "$main/.claude/worktrees/"*) ;; *) continue ;; esac
	finished "$w" || continue
	# Once per run, and only when something got this far.
	[ -n "$used" ] || used=$(cwds)$'\n'
	awk -v w="$w" '$0 == w || index($0, w "/") == 1 { f = 1 } END { exit f }' <<<"$used" || continue
	branch=$(git -C "$w" symbolic-ref -q --short HEAD || echo detached)
	if [ -n "$list" ]; then
		echo "would remove $w ($branch)"
	# --force: git refuses any worktree with a submodule without it, and
	# finished() has checked everything it would throw away.
	elif git -C "$main" worktree remove --force "$w" 2>/dev/null; then
		echo "removed finished worktree $w ($branch); the branch stays"
	fi
done
