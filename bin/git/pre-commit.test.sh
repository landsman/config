#!/usr/bin/env bash
# Self-check for ./pre-commit. No framework: it builds a throwaway repo, stages
# markdown in it, runs the real hook against the real deno, and asserts on what
# ended up staged.
set -eu

hook="$(cd "$(dirname "$0")" && pwd)/pre-commit"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

command -v deno >/dev/null || { echo "deno not installed - skipped"; exit 0; }

check() {  # check <name> <expected> <actual>
	if [ "$2" = "$3" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1"; echo "  expected: $2"; echo "  actual:   $3"; fails=$((fails + 1))
	fi
}

# -c on every call rather than a global config: this must not depend on, or
# write to, whatever git identity the machine running it has. gpgsign off
# because the real .gitconfig turns it on and a runner has no signing key.
git() { command git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

long="one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen"

cd "$tmp"
git init -q .
git commit -q --allow-empty -m init

# == the ordinary case: staged markdown is wrapped and re-staged
printf '# t\n\n%s\n' "$long" > a.md
git add a.md
out=$("$hook")
check "says which file it rewrote" "pre-commit: wrapped a.md" "$out"
check "wraps the staged file" "0" "$(awk 'length > 80' a.md | wc -l | tr -d ' ')"
check "onto two lines, not truncated" "2" "$(awk 'NR >= 3 && NF' a.md | wc -l | tr -d ' ')"
check "stages the wrapped version" "" "$(git diff --name-only -- a.md)"

# == a file with unstaged edits too is left alone, so the commit stays partial
printf '# t\n\n%s\n' "$long" > b.md
git add b.md
printf '# t\n\n%s\n\nunstaged\n' "$long" > b.md
out=$("$hook")
check "warns about the partly staged file" "pre-commit: b.md has unstaged changes - left unwrapped" "$out"
check "leaves it unwrapped" "${#long}" "$(awk 'NR==3{print length}' b.md)"

# == nothing markdown staged: silent, and it must not touch the tree
git commit -q -m "both files" # so the two above stop being staged
echo 'x' > c.txt
git add c.txt
out=$("$hook")
check "says nothing when no markdown is staged" "" "$out"

exit $((fails > 0))
