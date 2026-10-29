#!/usr/bin/env bash
# The title is the one thing here that fails silently: a wrong one is still a title.
set -euo pipefail
title="$(cd "$(dirname "$0")" && pwd)/title.sh"
fail=0
check() {
	local got
	got=$("$title" "${@:2}")
	if [[ $got == "$1" ]]; then echo "ok   $1"; else echo "FAIL want $1, got $got"; fail=1; fi
}

check "deps: bump latte/latte from 3.1.6 to 3.1.7" \
	"deps: bump latte/latte from 3.1.6 to 3.1.7 in /app" "latte/latte" "3.1.6" "3.1.7"
check "deps: bump latte/latte and tracy/tracy" \
	"deps: bump the composer group in /app with 2 updates" "latte/latte, tracy/tracy"
check "deps(pollos): bump astro, wrangler and @types/node" \
	"deps(pollos): bump the all group across 1 directory with 3 updates" "astro, wrangler, @types/node" "1" "2"
check "deps: bump a, b, c and 2 more" \
	"deps: bump the go group with 5 updates" "a,b,c,d,e"
check "deps: bump actions/checkout" "Bump actions/checkout" "actions/checkout"

exit $fail
