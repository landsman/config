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
# own names are fine, everywhere else they are not.
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

patterns=$(awk -v o="$owner" '!/^[[:space:]]*(#|$)/ && $1 != o { sub(/^[^[:space:]]+[[:space:]]+/, ""); print }' "$file")
if ! grep -qvE '^[[:space:]]*(#|$)' "$file"; then
	echo "forbidden-names: $file holds no patterns, refusing to commit unchecked." >&2
	exit 1
fi
# Every name belongs to this repo's owner: nothing is forbidden here. (An empty
# pattern list must not reach grep -f, where it would match every line.)
[ -n "$patterns" ] || exit 0

if [ $# -eq 0 ]; then
	# Added lines as file:line:text, so a hit points at the place to edit.
	text=$(git diff --cached -U0 --no-color | awk '
		/^\+\+\+ / { f = substr($0, 7); next }
		/^@@/ { split($3, a, ","); n = substr(a[1], 2); next }
		/^\+/ { print f ":" n ": " substr($0, 2); n++ }')
	where="staged"
else
	# Comment lines are git's template, not the message.
	text=$(grep -nv '^#' -- "$1" || true)
	where=$([ "$1" = - ] && echo "stdin" || echo "the commit message")
fi

hits=$(printf '%s\n' "$text" | grep -iE -f <(printf '%s\n' "$patterns") || true)
[ -z "$hits" ] && exit 0
echo "forbidden-names: a name that belongs to another owner, in $where:" >&2
printf '  %s\n' "$hits" >&2
echo "forbidden-names: use a placeholder (<org>, <host>) — see where-repos-live.md." >&2
exit 1
