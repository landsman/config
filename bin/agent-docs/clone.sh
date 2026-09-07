#!/usr/bin/env bash
# Clone the upstream documentation the agent rules point at.
#
#   clone.sh [root]        # root defaults to ~/projects
#
# Two rules — github-actions.md and forgejo-workflows.md — tell an agent to grep
# a local clone rather than recall syntax from training data. A pointer to a
# directory that is not on this machine sends it straight back to recall, which
# is the failure the pointer exists to prevent, so both rules point here and the
# flags live in one place.
#
# Re-running is also the update path: a clone already there is fast-forwarded.
set -eu

root=${1:-$HOME/projects}

# What to clone, and why each row looks the way it does, is repos.conf beside
# this file. This reads it: a directory, a url, and any paths to check out.
docs() {
	local name="$1" dest="$root/$1" url="$2"
	shift 2
	echo "== $name"

	if [ -d "$dest/.git" ]; then
		git -C "$dest" pull --ff-only
	elif [ -e "$dest" ]; then
		# Not a clone means somebody's working directory. Cloning over it is
		# not possible and deleting it is not this script's call.
		echo "   $dest exists and is not a git clone - left alone" >&2
	elif [ $# -gt 0 ]; then
		git clone --depth 1 --filter=blob:none --sparse "$url" "$dest"
		git -C "$dest" sparse-checkout set "$@"
	else
		git clone --filter=blob:none "$url" "$dest"
	fi
}

while read -r dest url paths; do
	# Blank lines and comments, so the file can explain itself. An unskipped
	# blank row is not harmless: it reads as an empty directory and a clone of
	# nothing, which is what the second-run count in the test caught.
	[ -n "$dest" ] || continue
	case $dest in \#*) continue ;; esac
	# $paths unquoted on purpose: it is a list of paths, not one path.
	# shellcheck disable=SC2086
	docs "$dest" "$url" $paths
done < "$(dirname "$0")/repos.conf"
