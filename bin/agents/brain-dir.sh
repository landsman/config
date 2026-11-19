#!/usr/bin/env bash
# Where the brain is checked out: BRAIN_DIR, kept in the machine-local drop-in
# every shell sources, because the path differs per machine and this repo is
# public. No default: a guessed path that is wrong reads as an empty brain.
#
#   brain-dir.sh          ask for the path, offer to clone it, save it (make brain)
#   brain-dir.sh get      print it: the environment first, then the drop-in
#   brain-dir.sh set DIR  save it as the drop-in's first export
#
# `get` reads the drop-in too, because a hook started by an IDE or a desktop app
# never sourced a shell profile. Where the drop-in is (LOCAL_ENV) and where the
# brain is cloned from (BRAIN_REMOTE) are set at the top of the Makefile; run
# outside make, this asks make for them.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
# Asked for only when needed: parsing the Makefile on every commit costs its
# $(shell) calls, and BRAIN_DIR is usually in the environment already.
drop_in() { echo "${LOCAL_ENV:-$(make -s --no-print-directory -C "$repo" print-LOCAL_ENV 2>/dev/null || true)}"; }

# Prints nothing rather than failing when the drop-in cannot be found (no make
# on an IDE's PATH): the caller then says BRAIN_DIR is unset, with its fix.
get() {
	if [ -n "${BRAIN_DIR:-}" ]; then echo "$BRAIN_DIR"; return; fi
	file=$(drop_in)
	[ -n "$file" ] && [ -r "$file" ] || return 0
	line=$(grep -m 1 '^export BRAIN_DIR=' "$file" || true)
	[ -n "$line" ] || return 0
	# The line is written with %q below, so the shell that sources it reads it
	# back. A hand-edited one may name an unset variable: it reads as empty, as in
	# the shell that sources it, rather than aborting the hook with "unbound variable".
	(
		set +u
		eval "$line"
		echo "${BRAIN_DIR:-}"
	) 2>/dev/null || true
}

# First export, so whatever the drop-in sets after it can build on it.
set_dir() {
	file=$(drop_in)
	[ -n "$file" ] || { echo "brain-dir: LOCAL_ENV is not set, see the top of $repo/Makefile" >&2; exit 1; }
	# Absolute, or each hook would resolve it against its own working directory.
	case $1 in /*) dir=$1 ;; *) dir=$PWD/$1 ;; esac
	[ ! -d "$dir" ] || dir=$(cd "$dir" && pwd)
	mkdir -p "$(dirname "$file")"
	[ -s "$file" ] || echo '# Machine-local and untracked on purpose - see .docs-llm/mcp-servers.md' >"$file"
	tmp=$(mktemp)
	# Through ENVIRON: awk -v would expand the backslashes %q writes.
	line="export BRAIN_DIR=$(printf %q "$dir")" awk '
		BEGIN { line = ENVIRON["line"] }
		/^export BRAIN_DIR=/ { next }
		!done && !/^#/ { print line; done = 1 }
		{ print }
		END { if (!done) print line }
	' "$file" >"$tmp"
	mv "$tmp" "$file"
	grep -H '^export BRAIN_DIR=' "$file"
}

ask() {
	was=$(get)
	read -r -p "Brain checkout [${was:-a path, e.g. ~/projects/brain}]: " dir
	dir=${dir:-$was}
	[ -n "$dir" ] || { echo "no path given, nothing saved" >&2; exit 1; }
	# Nothing relative: make -C has moved into the config repo, so it would land there.
	case $dir in
	"~" | "~/"*) dir=$HOME${dir#\~} ;;
	/*) ;;
	*) echo "write the full path, or one starting with ~/" >&2; exit 1 ;;
	esac
	if [ ! -d "$dir" ]; then
		remote=${BRAIN_REMOTE:-}
		read -r -p "$dir does not exist. Clone it from [${remote:-empty skips}]: " url
		remote=${url:-$remote}
		if [ -n "$remote" ]; then git clone "$remote" "$dir"; else echo "not cloned; clone it there before the next commit"; fi
	fi
	set_dir "$dir"
	echo "open a new shell so it is in the environment"
}

case ${1:-} in
get) get ;;
set) set_dir "${2:?usage: brain-dir.sh set DIR}" ;;
"") ask ;;
*) echo "usage: brain-dir.sh [get | set DIR]" >&2; exit 2 ;;
esac
