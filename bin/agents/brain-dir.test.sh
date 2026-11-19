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

bash "$script" set "/Volumes/My Disk/it's brain" >/dev/null
expect "a path with a space and a quote reads back whole" "/Volumes/My Disk/it's brain" "$(bash "$script" get)"
expect "and the shell sourcing the drop-in gets the same" "/Volumes/My Disk/it's brain" "$(bash -c ". \"$LOCAL_ENV\"; echo \"\$BRAIN_DIR\"")"

mkdir -p "$tmp/work/brain"
(cd "$tmp/work" && bash "$script" set brain >/dev/null)
expect "a relative path is saved absolute" "$(cd "$tmp/work/brain" && pwd)" "$(bash "$script" get)"

# A copy with no Makefile above it: nothing names the drop-in.
mkdir -p "$tmp/bare/bin/agents" && cp "$script" "$tmp/bare/bin/agents/"
out=$(env -u LOCAL_ENV bash "$tmp/bare/bin/agents/brain-dir.sh" get 2>&1); rc=$?
expect "a drop-in nobody can name: get prints nothing and succeeds" "0:" "$rc:$out"

# Every commit runs get: with BRAIN_DIR set it must not parse the Makefile.
mkdir -p "$tmp/stub" && printf '#!/bin/sh\ntouch "%s/make-ran"\nexit 1\n' "$tmp" >"$tmp/stub/make" && chmod +x "$tmp/stub/make"
env -u LOCAL_ENV PATH="$tmp/stub:$PATH" BRAIN_DIR=/b/env bash "$script" get >/dev/null
expect "BRAIN_DIR set: make is never run" "no" "$([ -e "$tmp/make-ran" ] && echo yes || echo no)"

bash "$script" bogus 2>/dev/null
expect "an unknown command is refused" "2" "$?"

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
