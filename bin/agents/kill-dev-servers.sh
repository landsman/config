#!/usr/bin/env bash
# Kill the dev servers an agent left running in a git worktree.
#
#   kill-dev-servers.sh <dir>    those started from <dir> or below it
#   kill-dev-servers.sh --all    those started from any agent worktree
#   kill-dev-servers.sh --hook   as Claude Code's SessionEnd hook: <dir> is the
#                                session's cwd, and only if that is a worktree
#
# --list in front of any of them shows what would be killed and kills nothing.
#
# A dev server here is a process of mine that listens on TCP and whose working
# directory is in scope. That takes no list of kinds: wrangler, a Spring Boot
# app and vite all listen, while the shell and the editor sitting in the same
# directory do not. It also takes a database or a language server started from
# there, which is what the end of a session wants anyway.
#
# Only the listeners are signalled. The wrappers above them, `npm exec` or a
# Gradle client, exit once their child is gone; checked on a real wrangler tree.
#
# ponytail: two sessions in one worktree — the first to end takes the other's
# server. Track which session started what the day that actually happens.
set -euo pipefail

usage() {
	echo "usage: kill-dev-servers.sh [--list] <dir> | --all | --hook" >&2
	exit 2
}

# The worktree a session ended in, from the hook's JSON on stdin. Fails when
# there is nothing to clean up.
session_worktree() {
	local input cwd git_dir common
	input=$(cat)
	# A /clear ends the session in name only; the work and its server go on.
	[ "$(jq -r '.reason // ""' <<<"$input")" != clear ] || return 1
	cwd=$(jq -r '.cwd // ""' <<<"$input")
	[ -d "$cwd" ] || return 1
	# Inherited from a git hook that runs Claude Code, these would answer for
	# the wrong repo.
	# shellcheck disable=SC2046 # git's own list of variable names, split on purpose
	unset $(git rev-parse --local-env-vars)
	[ "$(git -C "$cwd" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] || return 1
	# A linked worktree has a git dir of its own; the main checkout's is the
	# common one, and a server running out of that is one I started myself.
	git_dir=$(git -C "$cwd" rev-parse --path-format=absolute --git-dir)
	common=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir)
	[ "$git_dir" != "$common" ] || return 1
	git -C "$cwd" rev-parse --show-toplevel
}

# Pids of my processes that listen on TCP. lsof where there is one, which is
# every Mac; ss on a Linux without it, where it names the pid of own processes.
listeners() {
	if command -v lsof >/dev/null; then
		lsof -nP -a -u "$(id -u)" -iTCP -sTCP:LISTEN -Fp | sed -n 's/^p//p'
	else
		ss -Hltnp | grep -o 'pid=[0-9]*' | cut -d= -f2
	fi | sort -u
}

cwd_of() { # <pid>
	readlink "/proc/$1/cwd" 2>/dev/null ||
		lsof -a -d cwd -p "$1" -Fn 2>/dev/null | sed -n 's/^n//p'
}

in_scope() { # <cwd of a process>
	if [ -n "$dir" ]; then
		case "$1/" in "$dir"/*) return 0 ;; esac
	else
		case "$1" in */.claude/worktrees/*) return 0 ;; esac
	fi
	return 1
}

list=
[ "${1-}" != --list ] || { list=1; shift; }
dir=
case ${1-} in
--all) ;;
--hook)
	# A hook must never be the reason a session fails to close.
	trap 'exit 0' EXIT
	dir=$(session_worktree) || exit 0
	;;
'' | -*) usage ;;
*) dir=$1 ;;
esac
# Resolved, because that is how the kernel reports a process's cwd, and
# macOS's /tmp and /var are symlinks.
[ -z "$dir" ] || dir=$(cd -P "$dir" && pwd)

pids=()
for pid in $(listeners); do
	cwd=$(cwd_of "$pid")
	in_scope "$cwd" || continue
	pids+=("$pid")
	echo "$pid  $(ps -o comm= -p "$pid" | sed 's#.*/##')  $cwd"
done
[ ${#pids[@]} -gt 0 ] || { echo "no dev server running${dir:+ under $dir}"; exit 0; }
[ -z "$list" ] || exit 0

# SIGTERM first, so a server can close what it has open. Then SIGKILL for what
# is left: wrangler was found sitting through SIGTERM for days.
kill "${pids[@]}" 2>/dev/null || true
sleep 2
forced=0
for pid in "${pids[@]}"; do
	if kill -9 "$pid" 2>/dev/null; then forced=$((forced + 1)); fi
done
echo "killed ${#pids[@]}, $forced of them with SIGKILL"
