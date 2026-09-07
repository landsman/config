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
conf=${2:-$(dirname "$0")/repos.conf}

# What to clone, and why each section looks the way it does, is repos.conf
# beside this file.
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

die() { echo "$conf:$1: $2" >&2; exit 1; }

section= url= sparse= line=0 opened=0

# Clone the section that just ended. Sections are flushed on the next header and
# once more at EOF, which is the only reason `opened` exists: without it an empty
# file and a file whose first section is still being read look the same.
flush() {
	[ "$opened" -eq 1 ] || return 0
	[ -n "$url" ] || die "$1" "[$section] has no url"
	# $sparse unquoted on purpose: it is a list of paths, not one path.
	# shellcheck disable=SC2086
	docs "$section" "$url" $sparse
	section= url= sparse= opened=0
}

while read -r key sep value; do
	line=$((line + 1))
	case "${key:-#}" in
		\#*) continue ;;
		\[*\])
			flush "$line"
			section=${key#[}; section=${section%]}
			opened=1
			[ -n "$section" ] || die "$line" "empty section name"
			continue ;;
	esac

	[ "$opened" -eq 1 ] || die "$line" "$key= before any [section]"
	[ "$sep" = "=" ] || die "$line" "expected 'key = value', got '$key $sep'"

	case $key in
		url) url=$value ;;
		sparse) sparse=$value ;;
		*) die "$line" "unknown key '$key' in [$section] - url or sparse" ;;
	esac
done < "$conf"

flush "$line"
