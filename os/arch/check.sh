#!/usr/bin/env bash
# Everything under os/arch that can be checked without Omarchy: its tests, and a
# parse of its QML, which no other check reads. Run by .github/workflows/arch.yml.
#
#   bash os/arch/check.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
bun=(bun)
command -v bun >/dev/null || bun=(mise x -- bun)
# Qt 6 by path first: the shell is Qt 6, and on a desktop /usr/bin/qmllint can be Qt 5's.
qmllint=/usr/lib/qt6/bin/qmllint
[ -x "$qmllint" ] || qmllint=qmllint

rc=0
for t in $(git ls-files 'os/arch/*.test.sh'); do
	echo "== $t"
	"./$t" || { echo "FAIL $t"; rc=1; }
done
for t in $(git ls-files 'os/arch/*.test.ts'); do
	echo "== $t"
	"${bun[@]}" test "./$t" || { echo "FAIL $t"; rc=1; }
done
# Only a syntax error fails: the shell's own imports cannot resolve here, and
# qmllint reports those as warnings, which leave its exit status at 0.
for f in $(git ls-files 'os/arch/*.qml'); do
	echo "== $f"
	"$qmllint" "$f" >/dev/null 2>&1 || { echo "FAIL $f"; rc=1; }
done
exit "$rc"
