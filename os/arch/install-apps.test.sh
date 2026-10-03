#!/usr/bin/env bash
# Checks os/arch/install-apps.sh without an Arch machine and without installing
# anything: yay and pacman are stubs, and the script runs with a PATH of only
# those two, so no real package tool is ever reached — not even on an Arch box
# where a real yay exists, which is what makes the "no AUR helper" case safe to
# run anywhere. There is no key to pin here — an AUR build fetches a PKGBUILD and
# nothing this script verifies — so what this asserts is the quieter contract:
# installed packages are filtered out, only the missing ones reach yay in order,
# and a box with no helper fails loudly rather than half-installing.
#
#   bash os/arch/install-apps.test.sh

# The stubs are written to disk verbatim, so the unexpanded $@/$INSTALLED inside
# them are the point, not an oversight.
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/install-apps.sh"
# Resolved once with the real PATH and invoked by absolute path below, so the
# script can run under a PATH stripped to the stubs without losing its own shell.
BASH_BIN="$(command -v bash)"
FAILED=0

ok() { echo "ok   $1"; }
fail() { echo "FAIL $1"; FAILED=1; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else
	fail "$1"
	echo "       expected: $3"
	echo "       actual:   $2"
fi; }

# INSTALLED is what `pacman -Qq <pkg>` should report as present. yay logs the
# packages it is handed (flags dropped) to $YAY_LOG, so a case can assert the
# exact set and order. Absolute shebangs so the stubs execute under the
# stubs-only PATH the script runs with.
setup() {
	ROOT="$(mktemp -d)"
	BIN="$ROOT/bin"
	mkdir -p "$BIN"
	cat >"$BIN/pacman" <<'STUB'
#!/bin/bash
for p in $INSTALLED; do [ "$p" = "${!#}" ] && exit 0; done
exit 1
STUB
	cat >"$BIN/yay" <<'STUB'
#!/bin/bash
for a in "$@"; do case "$a" in -*) ;; *) echo "$a" ;; esac; done >"$YAY_LOG"
exit 0
STUB
	chmod +x "$BIN"/*
}

run() { PATH="$BIN" INSTALLED="$1" YAY_LOG="$ROOT/yay-installed" "$BASH_BIN" "$SCRIPT" 2>&1; }

echo "== every package already present"
setup
out="$(run "claude-desktop hyprmon-bin")"
check "exits 0" "$?" "0"
check "says so" "$(echo "$out" | tail -1)" "== AUR apps: all 2 installed"
if [ -f "$ROOT/yay-installed" ]; then fail "yay never ran"; else ok "yay never ran"; fi
rm -rf "$ROOT"

echo
echo "== one already there, one missing"
setup
out="$(run "hyprmon-bin")"
check "succeeds" "$?" "0"
check "yay is asked for exactly the missing one" "$(tr '\n' ' ' <"$ROOT/yay-installed")" "claude-desktop "
rm -rf "$ROOT"

echo
echo "== nothing present"
setup
out="$(run "")"
check "succeeds" "$?" "0"
check "yay gets both, in PACKAGES order" "$(tr '\n' ' ' <"$ROOT/yay-installed")" "claude-desktop hyprmon-bin "
rm -rf "$ROOT"

echo
echo "== no AUR helper on the box"
setup
rm -f "$BIN/yay"
out="$(run "")"
check "refuses, exit 1" "$?" "1"
case "$out" in *"yay not found"*) ok "says why" ;; *) fail "says why" ;; esac
if [ -f "$ROOT/yay-installed" ]; then fail "installs nothing"; else ok "installs nothing"; fi
rm -rf "$ROOT"

echo
if [ "$FAILED" -eq 0 ]; then echo "all passed"; else echo "failures"; fi
exit "$FAILED"
