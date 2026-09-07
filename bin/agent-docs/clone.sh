#!/usr/bin/env bash
# Clone the upstream documentation the agent rules point at.
#
#   clone.sh [root]        # root defaults to ~/projects
#
# Two rules — github-actions.md and forgejo-workflows.md — tell an agent to grep
# a local clone rather than recall syntax from training data. A pointer to a
# directory that is not on this machine sends it straight back to recall, which
# is the failure the pointer exists to prevent, and the rules each carry the
# clone command for exactly that reason. This is the same two commands in one
# place, so a fresh machine is one target rather than a scavenger hunt.
#
# Re-running is also the update path: a clone already there is fast-forwarded.
set -eu

root=${1:-$HOME/projects}

# dest <tab> url <tab> sparse paths
#
# A row with sparse paths is shallow as well: github/docs is the whole of
# docs.github.com and only content/actions is ever read here — 8.5 MB against a
# site — with `data/` in the checkout because the pages transclude snippets from
# it. A row without them is cloned whole, on purpose: forgejo/docs is read per
# version branch (`v16.0` is what a pinned instance runs, `next` is not), and a
# shallow clone has no branches to switch to.
repos=$(cat <<'EOF'
github/github_docs	https://github.com/github/docs.git	content/actions data/reusables/actions data/variables
codeberg/forgejo/docs	https://codeberg.org/forgejo/docs.git
EOF
)

while IFS=$'\t' read -r dest url sparse; do
	[ -n "$dest" ] || continue
	d="$root/$dest"
	echo "== $dest"

	if [ -d "$d/.git" ]; then
		git -C "$d" pull --ff-only
		continue
	fi

	# Something that is not a clone is somebody's working directory. Cloning
	# over it is not possible and deleting it is not this script's call.
	if [ -e "$d" ]; then
		echo "   $d exists and is not a git clone - left alone" >&2
		continue
	fi

	if [ -n "$sparse" ]; then
		git clone --depth 1 --filter=blob:none --sparse "$url" "$d"
		# Unquoted on purpose: the column is a list of paths, not one path.
		# shellcheck disable=SC2086
		git -C "$d" sparse-checkout set $sparse
	else
		git clone --filter=blob:none "$url" "$d"
	fi
done <<<"$repos"
