#!/usr/bin/env bash
# Kill the dev servers an agent left running.
#
#   kill-dev-servers.sh          every one on this machine
#   kill-dev-servers.sh <dir>    only those started from <dir> or below it
#   kill-dev-servers.sh --hook   as Claude Code's SessionEnd hook: the dir is the
#                                session's cwd, and only a git worktree counts
#
# An agent starts `wrangler pages dev` in a worktree to look at its change and
# the session ends without stopping it. The server reparents to init and keeps
# its port and its memory; ten of them were found four days old.
#
# A process belongs to a dir by its working directory, not its command line:
# `npm exec wrangler pages dev` names no path at all.
#
# ponytail: wrangler is the only kind so far. "Anything whose cwd is in the
# worktree" would need no list, and would also take the shell and the editor
# sitting in it.
set -euo pipefail

# One line per kind of dev server, matched against the whole command line and
# anchored at its start: the first word has to be what runs the server. Without
# the anchor a line matches wherever the words occur, and an editor open on
# "notes on wrangler dev" or an agent whose prompt mentions it dies as well.
patterns=(
	# `dev` only, so a `wrangler deploy` in flight is left alone.
	'^[^ ]*(node|npm|npx|pnpm|yarn|bunx?)( [^ ]+)* [^ ]*wrangler[^ ]* (pages )?dev'
	# Every workerd, so without a dir this also takes one a test run or a vite
	# dev server owns. Asking for all of them means all of them.
	'^[^ ]*workerd serve'
)
pattern=$(IFS='|'; echo "${patterns[*]}")

dir=${1-}
if [ "$dir" = --hook ]; then
	# A hook must never be the reason a session fails to close.
	trap 'exit 0' ERR
	input=$(cat)
	# A /clear ends the session in name only; the work and its server go on.
	[ "$(jq -r '.reason // ""' <<<"$input")" != clear ] || exit 0
	dir=$(jq -r '.cwd // ""' <<<"$input")
	[ -d "$dir" ] || exit 0
	# Inherited from a git hook that runs Claude Code, these would answer for
	# the wrong repo.
	# shellcheck disable=SC2046 # git's own list of variable names, split on purpose
	unset $(git rev-parse --local-env-vars)
	# Only a linked worktree: a server running out of the main checkout is one
	# I started myself. Its git dir is the common one; a worktree's is not.
	[ "$(git -C "$dir" rev-parse --path-format=absolute --git-dir)" != \
		"$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir)" ] || exit 0
	dir=$(git -C "$dir" rev-parse --show-toplevel)
fi
# The kernel reports a resolved path, and macOS's /tmp and /var are symlinks.
[ -z "$dir" ] || dir=$(cd -P "$dir" && pwd)

cwd_of() {
	readlink "/proc/$1/cwd" 2>/dev/null ||
		lsof -a -d cwd -p "$1" -Fn 2>/dev/null | sed -n 's/^n//p'
}

pids=()
for pid in $(pgrep -f "$pattern" || true); do
	if [ -n "$dir" ]; then
		case "$(cwd_of "$pid")/" in "$dir"/*) ;; *) continue ;; esac
	fi
	pids+=("$pid")
done
[ ${#pids[@]} -gt 0 ] || { echo "no dev server running${dir:+ under $dir}"; exit 0; }

# SIGTERM first, so workerd can close its sockets. wrangler itself was seen to
# sit through it, which is why the second pass exists and is not optional.
kill "${pids[@]}" 2>/dev/null || true
sleep 2
forced=0
for pid in "${pids[@]}"; do
	if kill -0 "$pid" 2>/dev/null; then
		kill -9 "$pid" 2>/dev/null || true
		forced=$((forced + 1))
	fi
done
echo "killed ${#pids[@]} dev server processes${dir:+ under $dir} ($forced needed SIGKILL)"
