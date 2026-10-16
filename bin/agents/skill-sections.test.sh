#!/usr/bin/env bash
# Self-check for ./skill-sections.sh, on small skills written here and on the
# repo's own. What it would get wrong silently: passing a list that dropped a
# section (a C19 deleted from SKILL.md), passing a name nothing defines, or
# passing a skill whose awk command opens a file that is not there.
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/skill-sections.sh"
skills="$(cd "$(dirname "$0")/../.." && pwd)/shared/.agents/skills"
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fails=0

skill() { # skill <name> ; SKILL.md on stdin, then criteria.md and sources.md written alongside
	mkdir -p "$t/$1"
	cat > "$t/$1/SKILL.md"
	printf '# Criteria\n\n## C1 One\n\ntext\n\n## C2 Two\n\ntext\n' > "$t/$1/criteria.md"
	printf '# Sources\n\n## Go\n\ntext\n' > "$t/$1/sources.md"
}

check() { # check <behaviour> <pass|fail> <dir> [expected output fragment]
	local name=$1 want=$2 got out
	if out=$("$script" check "$3" 2>&1); then got=pass; else got=fail; fi
	if [ "$got" = "$want" ] && { [ -z "${4:-}" ] || grep -qF -- "$4" <<< "$out"; }; then
		echo "ok   $name"
	else
		echo "FAIL $name (want $want, got $got: $out)"
		fails=$((fails + 1))
	fi
}

list="    awk '/^## C1 /{f=1;print;next} /^## /{f=0} f' ~/.agents/skills/x/criteria.md
    awk '/^## Go/{f=1;print;next} /^## /{f=0} f' ~/.agents/skills/x/sources.md"
named="Sections: \`Go\`."

printf '%s\n\n%s\n\n- **C1 One**\n- **C2 Two**\n' "$list" "$named" | skill good
check "a list naming every section passes" pass "$t/good"

printf '%s\n\n%s\n\n- **C1 One**\n' "$list" "$named" | skill dropped
check "a section the list dropped fails" fail "$t/dropped" "criteria.md has C2"

printf '%s\n\n%s\n\n- **C1 One**\n- **C2 Two**\n- **C3 Three**\n' "$list" "$named" | skill extra
check "an identifier with no section fails" fail "$t/extra" "SKILL.md names C3"

printf '%s\n\n%s\n\nSee C1 and C2.\n\n- **C1 One**\n' "$list" "$named" | skill ranged
check "an identifier only in prose, not as a list item, fails" fail "$t/ranged" "criteria.md has C2"

printf '%s\n\n- **C1 One**\n- **C2 Two**\n' "$list" | skill unnamed
check "a titled section the list does not name fails" fail "$t/unnamed" '"Go"'

printf '%s\n\n%s\n\n- **C1 One**, then C12 and CVE-2024-1 in prose\n- **C2 Two**\n' "$list" "$named" | skill prose
check "an identifier named in prose needs a section too" fail "$t/prose" "SKILL.md names C12"

printf "    awk '/^## X/{f=1;print;next} /^## /{f=0} f' missing.md\n" | skill gone
check "an awk command opening a missing file fails" fail "$t/gone" "missing.md, which does not exist"

if out=$("$script" all "$skills" 2>&1); then
	echo "ok   every skill in this repo agrees with its detail files"
else
	echo "FAIL every skill in this repo agrees with its detail files: $out"
	fails=$((fails + 1))
fi

exit $((fails > 0))
