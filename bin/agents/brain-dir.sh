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
# never sourced a shell profile. LOCAL_ENV overrides the drop-in's path, for tests.
set -euo pipefail
file=${LOCAL_ENV:-$HOME/.config/bash_aliases.d/99-local.sh}
remote=ssh://git@git-ssh.insuit.cz/landsman/brain.git

get() {
	if [ -n "${BRAIN_DIR:-}" ]; then echo "$BRAIN_DIR"; return; fi
	[ -r "$file" ] || return 0
	sed -n 's/^export BRAIN_DIR=//p' "$file" | head -n 1
}

# First export, so whatever the drop-in sets after it can build on it.
set_dir() {
	mkdir -p "$(dirname "$file")"
	[ -s "$file" ] || echo '# Machine-local and untracked on purpose - see .docs-llm/mcp-servers.md' >"$file"
	tmp=$(mktemp)
	awk -v line="export BRAIN_DIR=$1" '
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
	suggested=${was:-$HOME/projects/landsman/brain}
	read -r -p "Brain checkout [$suggested]: " dir
	dir=${dir:-$suggested}
	dir=${dir/#\~/$HOME}
	if [ ! -d "$dir" ]; then
		read -r -p "$dir does not exist. Clone $remote there? [Y/n] " yes
		case $yes in n | N | no) echo "not cloned; clone it there before the next commit" ;; *) git clone "$remote" "$dir" ;; esac
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
