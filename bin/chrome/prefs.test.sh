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
# The accented value is not decoration. json.dump defaults to ensure_ascii=True,
# which would rewrite it as \u0159 - a key this script never touches, changed
# anyway, which is the one thing it promises not to do.
printf '{"vertical_tabs":{"enabled":false,"enabled_first_time":true},"profile":{"keep":"m\xc3\xa9","name":"Nastaven\xc3\xad"}}' > "$tmp/Preferences"

# pgrep says "nothing running", so the guard lets the write through.
printf '#!/bin/sh\nexit 1\n' > "$tmp/pgrep"
chmod +x "$tmp/pgrep"

out=$(PATH="$tmp:$PATH" CHROME_PREFS="$tmp/Preferences" "$script")
# ensure_ascii=False here too, or the helper escapes what it reports and an
# accented expectation below could never match it.
read_key() { python3 -c 'import json,sys;d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."): d=d[k]
print(json.dumps(d, ensure_ascii=False))' "$tmp/Preferences" "$1"; }

check "the file is still valid JSON" '0' "$(python3 -m json.tool "$tmp/Preferences" >/dev/null 2>&1; echo $?)"
check "vertical tabs are on" 'true' "$(read_key vertical_tabs.enabled)"
check "the sibling key survives" 'true' "$(read_key vertical_tabs.enabled_first_time)"
check "an unrelated subtree survives" '"mé"' "$(read_key profile.keep)"
# Byte-level, not value-level: read_key would decode an escape back to the same
# string, so it cannot see this. grep the file itself.
check "non-ASCII stays a character, not \\uXXXX" '0' "$(grep -c '\\u' "$tmp/Preferences")"
check "and is still the right character" '1' "$(grep -c 'Nastavení' "$tmp/Preferences")"
check "a missing parent is created" 'false' "$(read_key side_panel.is_right_aligned)"
# The one number pinned by hand, and deliberately: adding a setting to prefs.py
# should not slip in without this file noticing. Everything below derives the
# keys from the dry run instead.
applied=$(grep -c '^set ' <<<"$out")
check "it reports what it wrote" '4' "$applied"

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
check "dry run and the real run agree" "$applied" "$(grep -c '^set ' <<<"$out")"

# The list lives in prefs.py, so take it from the dry run rather than repeat it
# here: a setting added there is covered by this the moment it is added, and a
# key that prints but does not reach the file fails. Both halves matter - the
# old version pinned the count at 4 with a regex that also pinned the shape, so
# a legitimate string value with a space in it was quietly dropped from the
# count instead of failing, and the two wrongs cancelled.
missing=
for k in $(sed -n 's/^set \([^ ]*\) = .*/\1/p' <<<"$out"); do
	read_key "$k" >/dev/null 2>&1 || missing="$missing $k"
done
check "every key the dry run names is set" '' "$missing"

# An unreadable profile is the macOS case: Chrome's data directory carries
# com.apple.macl, so a terminal without Full Disk Access gets EPERM while
# `test -f` still says the file is there. chmod 000 is the portable stand-in.
# Skipped as root, which ignores the mode and would read it anyway.
#
# The pgrep stub goes back to "nothing running" first. The block above left it
# saying Chrome is up, and that guard would answer before this one - the test
# would pass on the wrong refusal.
printf '#!/bin/sh\nexit 1\n' > "$tmp/pgrep"
if [ "$(id -u)" != 0 ]; then
	chmod 000 "$tmp/Preferences"
	set +e
	out=$(PATH="$tmp:$PATH" CHROME_PREFS="$tmp/Preferences" "$script" 2>&1); status=$?
	set -e
	chmod 600 "$tmp/Preferences"
	check "refuses an unreadable profile" '1' "$status"
	check "and points at Full Disk Access" '1' "$(grep -c 'Full Disk Access' <<<"$out")"
	# The status alone proves nothing: the traceback this replaced also exited
	# non-zero. What regressed is the python reaching a file it cannot open.
	check "without a python traceback" '0' "$(grep -c 'Traceback' <<<"$out")"
else
	echo "skip refuses an unreadable profile (running as root)"
fi

# A mistyped flag must refuse, not fall through to the write path - that is the
# whole reason --dry-run is spelled out rather than "anything but a flag".
set +e
out=$(CHROME_PREFS="$tmp/Preferences" "$script" --dryrun 2>&1); status=$?
set -e
check "an unknown argument refuses" '2' "$status"
check "and prints the usage" '1' "$(grep -c '^usage: ' <<<"$out")"

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
