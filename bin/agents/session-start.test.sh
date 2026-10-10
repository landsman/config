#!/usr/bin/env bash
# Self-check for ./session-start.sh: a throwaway $HOME, the repo's real
# shared/.agents as the list of what should be linked.
set -eu

dir="$(cd "$(dirname "$0")" && pwd)"
hook="$dir/session-start.sh"
repo="$(cd "$dir/../.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
export HOME="$tmp"

check() { # check <name> <substring> <yes|no>: is the substring in the output?
	local out
	out=$(bash "$hook")
	if { [ "$3" = yes ] && [[ "$out" == *"$2"* ]]; } || { [ "$3" = no ] && [[ "$out" != *"$2"* ]]; }; then
		echo "ok   $1"
	else
		echo "FAIL $1"; echo "  got: $out"; fails=$((fails + 1))
	fi
}

check "an unlinked rule is named" ".agents/rules/attribution.md" yes
check "no brain, no index" "Brain index" no
ln -s "$repo/shared/.agents" "$tmp/.agents"
check "everything linked, nothing to say" "Not linked" no

mkdir -p "$tmp/projects/landsman/brain/wiki"
idx="$tmp/projects/landsman/brain/wiki/index.md"
printf '# Index\n\n## Tools\n\n- [Page](page.md) — what the page holds\n- Not written yet — why it would be\n' > "$idx"
check "the index keeps the title and link" "- [Page](page.md)" yes
check "and drops the description" "what the page holds" no
check "a page with no link keeps its title" "- Not written yet" yes

for i in $(seq 300); do echo "- [A page title number $i](a-page-title-number-$i.md) — d"; done >> "$idx"
check "a long index falls back to titles" "- A page title number 300" yes
check "without the links" "(a-page-title-number-300.md)" no

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
