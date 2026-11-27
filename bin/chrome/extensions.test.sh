#!/usr/bin/env bash
# Self-check for ./extensions.sh, against a throwaway folder and list.
# What it would get wrong silently: a comment line taken for an id, a file
# Chrome cannot parse, or a typo that writes half the list before failing.
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/extensions.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

check() {  # check <behaviour> <expected> <actual>
	if [ "$2" = "$3" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1"; echo "  expected: $2"; echo "  actual:   $3"; fails=$((fails + 1))
	fi
}

export CHROME_EXTERNAL_EXTENSIONS="$tmp/out"
keepa=neebplgakaahbhdphmkckjjcegoiijjo
printf '# a comment\n\n%s  Keepa\n' "$keepa" >"$tmp/list"

describe_expected_use() {
	CHROME_EXTENSIONS_LIST="$tmp/list" "$script" >/dev/null
	check "one file per id, comments and blanks skipped" "$keepa.json" "$(ls "$tmp/out")"
	check "the file points Chrome at the Web Store" 'https://clients2.google.com/service/update2/crx' \
		"$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["external_update_url"])' "$tmp/out/$keepa.json")"
	before=$(cat "$tmp/out/$keepa.json")
	CHROME_EXTENSIONS_LIST="$tmp/list" "$script" >/dev/null
	check "idempotent" "$before" "$(cat "$tmp/out/$keepa.json")"
	check "the repo's own list is valid" '0' \
		"$(CHROME_EXTERNAL_EXTENSIONS="$tmp/repo" "$script" >/dev/null 2>&1; echo $?)"
}

describe_bad_input() {
	rm -rf "$tmp/out"
	printf '%s  Keepa\nhttps://chromewebstore.google.com/detail/x  pasted a URL\n' "$keepa" >"$tmp/bad"
	set +e
	out=$(CHROME_EXTENSIONS_LIST="$tmp/bad" "$script" 2>&1); status=$?
	set -e
	check "a line that is not an id refuses" '1' "$status"
	check "and names it" '1' "$(grep -c 'not a Chrome extension id' <<<"$out")"
	check "before writing any of the list" 'no' "$([ -e "$tmp/out" ] && echo yes || echo no)"
}

describe_expected_use
describe_bad_input

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
