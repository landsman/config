#!/usr/bin/env bash
# Self-check for ./prefs.sh. Runs it against a throwaway Preferences file via
# $CHROME_PREFS, with a `pgrep` stub on PATH, so it never touches the real
# Chrome profile and gives the same answer on a runner with no Chrome at all.
set -eu

script="$(cd "$(dirname "$0")" && pwd)/prefs.sh"
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

# A stand-in profile: one key this repo writes into, and one it must not touch.
# The nested "keep" is the point — Chrome's Preferences is one blob, and a patch
# that rewrites a whole subtree instead of a leaf loses site permissions.
printf '{"vertical_tabs":{"enabled":false,"enabled_first_time":true},"profile":{"keep":"me"}}' > "$tmp/Preferences"

# pgrep says "nothing running", so the guard lets the write through.
printf '#!/bin/sh\nexit 1\n' > "$tmp/pgrep"
chmod +x "$tmp/pgrep"

out=$(PATH="$tmp:$PATH" CHROME_PREFS="$tmp/Preferences" "$script")
read_key() { python3 -c 'import json,sys;d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."): d=d[k]
print(json.dumps(d))' "$tmp/Preferences" "$1"; }

check "the file is still valid JSON" '0' "$(python3 -m json.tool "$tmp/Preferences" >/dev/null 2>&1; echo $?)"
check "vertical tabs are on" 'true' "$(read_key vertical_tabs.enabled)"
check "the sibling key survives" 'true' "$(read_key vertical_tabs.enabled_first_time)"
check "an unrelated subtree survives" '"me"' "$(read_key profile.keep)"
check "a missing parent is created" 'false' "$(read_key side_panel.is_right_aligned)"
check "it reports what it wrote" '4' "$(grep -c '^set ' <<<"$out")"

# Running it twice must not drift — this is what `make chrome` does on every
# machine, every time.
before=$(cat "$tmp/Preferences")
PATH="$tmp:$PATH" CHROME_PREFS="$tmp/Preferences" "$script" >/dev/null
check "idempotent" "$before" "$(cat "$tmp/Preferences")"

# The guard: with Chrome running the write is discarded on its exit, so it must
# refuse rather than pretend.
printf '#!/bin/sh\nexit 0\n' > "$tmp/pgrep"
set +e
out=$(PATH="$tmp:$PATH" CHROME_PREFS="$tmp/Preferences" "$script" 2>&1); status=$?
set -e
check "refuses while Chrome runs" '1' "$status"
check "and says why" '1' "$(grep -c 'quit Chrome' <<<"$out")"

# --dry-run must not need a profile, or reach one.
out=$(CHROME_PREFS="$tmp/absent" "$script" --dry-run)
check "dry run writes nothing" 'no' "$([ -f "$tmp/absent" ] && echo yes || echo no)"
check "dry run lists every key" '4' "$(grep -c '^set ' <<<"$out")"

# Same shape the script parses: key, one space, JSON value. A pasted line with a
# space in the value would set the key to garbage without this.
keys=$(sed -n 's/^set \([^ ]*\) .*/\1/p' <<<"$out")
check "no key listed twice" '' "$(sort <<<"$keys" | uniq -d)"
check "every value is one JSON token" '4' \
	"$(grep -c '^set [a-z_.]* [^ ]*$' <<<"$out")"

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
