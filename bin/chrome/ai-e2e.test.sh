#!/usr/bin/env bash
# Self-check for ./ai-e2e.sh device-id against a throwaway data directory.
# `start` is not exercised: it would open a browser.
set -eu

script="$(cd "$(dirname "$0")" && pwd)/ai-e2e.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
export HOME="$tmp"

check() { # check <name> <expected output> <actual output>
	if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "  got: $3"; fails=$((fails + 1)); fi
}

check "no data directory, no id" "" "$(bash "$script" device-id)"

ext="$tmp/.chrome-ai-e2e/Default/Local Extension Settings/fcoeoabgfenejglbffodgkkbkcdhcgfn"
mkdir -p "$ext"
old=11111111-2222-3333-4444-555555555555
new=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
# LevelDB keeps every write, so the file holds the old value before the new one.
printf '\x01\x02bridgeDeviceId\x00"%s"\x03 other bytes \x04bridgeDeviceId\x00"%s"\x05' "$old" "$new" > "$ext/000003.log"
check "the newest id wins" "$new" "$(bash "$script" device-id)"

bash "$script" nonsense 2>/dev/null && status=0 || status=$?
check "an unknown command fails" "2" "$status"

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
