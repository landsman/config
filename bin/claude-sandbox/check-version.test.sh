#!/usr/bin/env bash
# Self-check for ./check-version.sh: the major comparison, no network.
set -eu

dir="$(cd "$(dirname "$0")" && pwd)"
fails=0

check() { # check <name> <yes|no> <pinned> <latest>
	if "$dir/check-version.sh" newer-major "$3" "$4"; then got=yes; else got=no; fi
	if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}

check "a new major is reported" yes 2.1.296 3.0.0
check "a new minor is not" no 2.1.296 2.2.0
check "a patch is not" no 2.1.296 2.1.300
check "the same version is not" no 2.1.296 2.1.296
check "2 digits compare as numbers, not text" yes 9.0.0 10.0.0

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
