#!/usr/bin/env bash
# Refuses a commit that names a client or an employer outside their own repos —
# the check where-repos-live.md asks for before anything leaves the machine.
#
#   forbidden-names.sh          the staged diff (pre-commit)
#   forbidden-names.sh <file>   a commit message file (commit-msg), or any text
#   forbidden-names.sh -        stdin, e.g. a PR body before it is posted
#
# Wired as a config-based hook in .gitconfig (git 2.54+), not through
# core.hooksPath: that would replace every repo's own hooks, and a husky or a
# pre-commit framework setting its own path would switch this one off.
#
# The names are not in this repo, which is public — listing them here would be
# the leak. They live in the file `git config forbiddenNames.file` points at,
# one `<owner> <extended regex>` per line, # comments allowed. <owner> is the
# directory under ~/projects the name belongs to: inside that owner's repos its
# own names are fine, everywhere else they are not. A name shared by several
# folders (a client whose product lives under another one) lists them all,
# comma-separated: `acme,acme-holding acme`.
set -euo pipefail

file=$(git config --get forbiddenNames.file || true)
# Unset means a machine this repo never set up (a CI runner): nothing to check.
[ -n "$file" ] || exit 0
file="${file/#\~/$HOME}"
if [ ! -f "$file" ]; then
	echo "forbidden-names: $file is missing, refusing to commit unchecked." >&2
	echo "forbidden-names: clone the brain, or skip this repo: git config hook.forbidden-names.enabled false" >&2
	exit 1
fi

# The main checkout, also from a linked worktree, which may sit outside ~/projects.
repo=$(cd "$(git rev-parse --path-format=absolute --git-common-dir)/.." && pwd -P)
case "$file" in
	# The repo that holds the list is private by definition.
	"$repo"/*) exit 0 ;;
esac
owner=""
case "$repo" in
	"$HOME"/projects/*) owner=${repo#"$HOME"/projects/}; owner=${owner%%/*} ;;
esac

# Trailing whitespace or a CR first: `acme ` would otherwise leave an empty
# pattern, and an empty pattern matches every line.
patterns=$(awk -v o="$owner" '{ sub(/[[:space:]]+$/, "") }
	!/^[[:space:]]*(#|$)/ && index("," $1 ",", "," o ",") == 0 { sub(/^[^[:space:]]+[[:space:]]+/, ""); print }' "$file")
if ! grep -qvE '^[[:space:]]*(#|$)' "$file"; then
	echo "forbidden-names: $file holds no patterns, refusing to commit unchecked." >&2
	exit 1
fi
# Every name belongs to this repo's owner: nothing is forbidden here. (An empty
# pattern list must not reach grep -f, where it would match every line.)
[ -n "$patterns" ] || exit 0

if [ $# -eq 0 ]; then
	# Added lines as file:line:text, so a hit points at the place to edit. The
	# prefixes are pinned against diff.noprefix, and `+++ ` is a header only
	# before a file's first hunk: inside one it is an added line starting `++ `.
	text=$(git diff --cached -U0 --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/ | awk '
		/^diff --git / { h = 1; next }
		h && /^\+\+\+ / { f = substr($0, 7); next }
		/^@@/ { h = 0; split($3, a, ","); n = substr(a[1], 2); next }
		/^\+/ && !h { print f ":" n ": " substr($0, 2); n++ }')
	# The names too: an empty or binary file has no added line to carry its path.
	text+=$'\n'$(git diff --cached --name-only --diff-filter=d | sed 's/$/: (file name)/')
	where="staged"
elif [ "$1" = - ]; then
	# A PR body: a line starting with # is a Markdown heading, not a comment.
	text=$(grep -n '' || true)
	where="stdin"
else
	# git's template comments are not the message, and neither is the diff that
	# `commit -v` appends below the scissors line — its removed lines included.
	text=$(sed '/^# -\{24\} >8 -\{24\}$/,$d' "$1" | grep -nv '^#' || true)
	where="the commit message"
fi

hits=$(printf '%s\n' "$text" | grep -iE -f <(printf '%s\n' "$patterns") || true)
[ -z "$hits" ] && exit 0
echo "forbidden-names: a name that belongs to another owner, in $where:" >&2
printf '  %s\n' "$hits" >&2
echo "forbidden-names: use a placeholder (<org>, <host>) — see where-repos-live.md." >&2
exit 1
