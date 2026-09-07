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

# A pinned clone lands on a detached HEAD, and git says so in ten lines of
# advice aimed at somebody who did not mean it. Set through the environment
# rather than on each command line, so the commands stay readable.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=advice.detachedHead GIT_CONFIG_VALUE_0=false

root=${1:-$HOME/projects}
conf=${2:-$(dirname "$0")/repos.conf}

# What to clone, and why each section looks the way it does, is repos.conf
# beside this file.
docs() {
	local name="$1" dest="$root/$1" url="$2" ref="$3"
	shift 3
	echo "== $name"

	if [ -d "$dest/.git" ]; then
		if [ -n "$ref" ]; then
			# Pinned, so there is nothing to fast-forward: fetch that one ref
			# and sit on it. Bumping the version in repos.conf is what moves a
			# pinned clone, which is the point of pinning it.
			git -C "$dest" fetch --depth 1 origin "$ref"
			git -C "$dest" checkout --quiet --detach FETCH_HEAD
		else
			git -C "$dest" pull --ff-only
		fi
		return
	fi

	if [ -e "$dest" ]; then
		# Not a clone means somebody's working directory. Cloning over it is
		# not possible and deleting it is not this script's call.
		echo "   $dest exists and is not a git clone - left alone" >&2
		return
	fi

	# Naming paths is what makes a clone shallow: a repository checked out for
	# three directories of documentation has no use for its history.
	local -a opts=(--filter=blob:none)
	[ $# -eq 0 ] || opts+=(--depth 1 --sparse)
	[ -z "$ref" ] || opts+=(--branch "$ref")

	git clone "${opts[@]}" "$url" "$dest"
	[ $# -eq 0 ] || git -C "$dest" sparse-checkout set "$@"
}

# Not every documentation site is a git repository. A site publishing llms.txt
# lists its pages as markdown, which is the same thing arriving over HTTP: fetch
# the list, fetch what it names, keep the site's own directory structure.
#
# Only links ending in `.md` are followed. That is not fussiness — Stripe's list
# opens with a paragraph of prose that happens to contain a URL, and a downloader
# taking every link creates a directory named after the sentence.
llmstxt() {
	local name="$1" dest="$root/$1" url="$2" listed missing
	echo "== $name"
	mkdir -p "$dest"

	# The list itself is kept: a diff of it is how a page that upstream added or
	# dropped becomes visible.
	curl -sSfL -o "$dest/llms.txt" "$url"
	listed=$(grep -oE 'https?://[^)"'"'"'[:space:]]+\.md' "$dest/llms.txt" | sort -u)
	[ -n "$listed" ] || { echo "   no .md links in $url" >&2; return; }

	# -z asks for the file only if it changed, so a re-run is a few hundred 304s
	# rather than a few hundred downloads. Five at a time, which is what the site
	# would see from one browser opening a page.
	printf '%s\n' "$listed" | DEST="$dest" xargs -P 5 -n 8 sh -c '
		for u; do
			p=${u#*://}; p=${p#*/}
			mkdir -p "$DEST/$(dirname "$p")"
			if [ -f "$DEST/$p" ]; then
				curl -sSfL -z "$DEST/$p" -o "$DEST/$p" "$u" || echo "   gone: $u" >&2
			else
				curl -sSfL -o "$DEST/$p" "$u" || echo "   gone: $u" >&2
			fi
		done' _

	missing=$(printf '%s\n' "$listed" | wc -l | tr -d ' ')
	echo "   $missing pages listed, $(find "$dest" -name '*.md' | wc -l | tr -d ' ') on disk"
}

die() { echo "$conf:$1: $2" >&2; exit 1; }

section= url= llms= ref= sparse= line=0 opened=0

# Clone the section that just ended. Sections are flushed on the next header and
# once more at EOF, which is the only reason `opened` exists: without it an empty
# file and a file whose first section is still being read look the same.
flush() {
	[ "$opened" -eq 1 ] || return 0

	if [ -n "$url" ] && [ -n "$llms" ]; then
		die "$1" "[$section] has url and llms - a section is one or the other"
	elif [ -n "$url" ]; then
		# $sparse unquoted on purpose: it is a list of paths, not one path.
		# shellcheck disable=SC2086
		docs "$section" "$url" "$ref" $sparse
	elif [ -n "$llms" ]; then
		[ -z "$ref$sparse" ] || die "$1" "[$section] has llms with ref or sparse, which only a clone can use"
		llmstxt "$section" "$llms"
	else
		die "$1" "[$section] has no url or llms"
	fi

	section= url= llms= ref= sparse= opened=0
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
		llms) llms=$value ;;
		ref) ref=$value ;;
		sparse) sparse=$value ;;
		*) die "$line" "unknown key '$key' in [$section] - url, llms, ref or sparse" ;;
	esac
done < "$conf"

flush "$line"
