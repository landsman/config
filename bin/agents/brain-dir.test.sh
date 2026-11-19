#!/usr/bin/env bash
# Self-check for ./brain-dir.sh: a throwaway drop-in, no shell profile touched.
set -u
script="$(cd "$(dirname "$0")" && pwd)/brain-dir.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unset BRAIN_DIR
export LOCAL_ENV="$tmp/99-local.sh"
fails=0
expect() { # expect <name> <expected> <actual>
	if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "  want: $2"; echo "  got:  $3"; fails=$((fails + 1)); fi
}

expect "nothing saved, nothing printed" "" "$(bash "$script" get)"

printf '# header\nexport AZDO_ORG=org\n' >"$LOCAL_ENV"
bash "$script" set /b/one >/dev/null
expect "saved before the other exports" "export BRAIN_DIR=/b/one" "$(sed -n 2p "$LOCAL_ENV")"
expect "and the rest is kept" "export AZDO_ORG=org" "$(sed -n 3p "$LOCAL_ENV")"

bash "$script" set /b/two >/dev/null
expect "saved again, replaced rather than added" "1" "$(grep -c BRAIN_DIR "$LOCAL_ENV")"
expect "get reads the drop-in" "/b/two" "$(bash "$script" get)"
expect "the environment wins over the drop-in" "/b/env" "$(BRAIN_DIR=/b/env bash "$script" get)"

rm "$LOCAL_ENV"
bash "$script" set /b/new >/dev/null
expect "a missing drop-in is created" "export BRAIN_DIR=/b/new" "$(grep '^export' "$LOCAL_ENV")"

bash "$script" bogus 2>/dev/null
expect "an unknown command is refused" "2" "$?"

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
