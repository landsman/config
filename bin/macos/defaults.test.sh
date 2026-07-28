#!/usr/bin/env bash
# Self-check for ./defaults.sh. Runs it in --dry-run with a `defaults` stub on
# PATH, so the suite is safe on the developer's Mac and runs on a Linux runner
# that has no `defaults` at all.
set -eu

script="$(cd "$(dirname "$0")" && pwd)/defaults.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

check() {  # check <name> <expected> <actual>
	if [ "$2" = "$3" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1"; echo "  expected: $2"; echo "  actual:   $3"; fails=$((fails + 1))
	fi
}

# The point of the stub: --dry-run must not reach the real binary. Without this
# a broken guard would rewrite the settings of whoever ran `make qa`.
printf '#!/bin/sh\necho "STUB CALLED: $*"\nexit 1\n' > "$tmp/defaults"
chmod +x "$tmp/defaults"
out=$(PATH="$tmp:$PATH" "$script" --dry-run)

check "dry run never calls defaults" '' "$(grep 'STUB CALLED' <<<"$out" || true)"
check "every line is a defaults write or import" '0' \
	"$(grep -cv -e "^defaults \(-currentHost \)\?write [^ ]* '[^']*' " -e '^defaults import ' <<<"$out")"

# The domain import is the one line that depends on a second file: a rename or a
# stray `git rm` turns it into a runtime failure on a fresh Mac and nowhere else.
plist=$(sed -n 's/^defaults import [^ ]* //p' <<<"$out")
check "imports exactly one plist" '1' "$(wc -l <<<"$plist" | tr -d ' ')"
check "the imported plist exists" 'yes' "$([ -f "$plist" ] && echo yes || echo no)"
check "it is the hotkeys domain" '1' "$(grep -c AppleSymbolicHotKeys "$plist" || true)"
# XML, not binary: the point of committing it is that a change shows up as a diff.
check "the plist is XML" '1' "$(head -1 "$plist" | grep -c '^<?xml' || true)"
if command -v plutil >/dev/null; then
	check "the plist parses" '0' "$(plutil -lint "$plist" >/dev/null 2>&1; echo $?)"
fi

# domain + key, one per line — the quotes are what make a key with spaces
# survive this intact.
pairs=$(sed -n "s/^defaults write \([^ ]*\) '\([^']*\)'.*/\1 \2/p" <<<"$out")

# A setting written twice is silently the last one — and with 40-odd lines in
# eleven domains, the same key landing in two sections is the way this file rots.
check "no key written twice" '' "$(sort <<<"$pairs" | uniq -d)"

check "menu bar keys survive their spaces" '4' \
	"$(grep -c "^com.apple.controlcenter NSStatusItem Preferred Position " <<<"$pairs")"

# Cheap sanity that the list is still the list, not an empty loop.
check "writes every domain" '11' "$(cut -d' ' -f1 <<<"$pairs" | sort -u | wc -l | tr -d ' ')"

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
