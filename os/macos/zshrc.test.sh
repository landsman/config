#!/usr/bin/env bash
# Checks that the completion path `make apps` relies on is actually wired up.
#
# Every completion in the Brewfile — stripe's included — reaches the shell the
# same way: the formula installs `_name` into $HOMEBREW_PREFIX/share/zsh/
# site-functions, and `brew shellenv` in .zshrc puts that directory on fpath.
# Nothing else is written down for it, so nothing else fails loudly when it
# breaks: reorder .zshrc so shellenv runs after the completion block, or drop
# the line, and every brew-installed completion goes quiet with no error. That
# is what this asserts, because it is the one step of the install nobody sees.
#
# Read-only, like the rest of `make qa`: the rc is sourced under its own
# ZDOTDIR with $HOME left alone, and nothing is installed or written.
#
#   bash os/macos/zshrc.test.sh

set -uo pipefail

ZSHRC="$(cd "$(dirname "$0")" && pwd)/.zshrc"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
FAILED=0

ok() { echo "ok   $1"; }
fail() {
	echo "FAIL $1"
	FAILED=1
}
check() { if [ "$2" = "$3" ]; then ok "$1"; else
	fail "$1"
	echo "       expected: $3"
	echo "       actual:   $2"
fi; }

# macOS-only by nature — the Linux boxes are bash, see .bashrc — and it needs a
# real Homebrew to have a prefix to assert about. Skipping is the honest result
# on the Ubuntu leg of CI rather than a pass that checked nothing.
if [ "$(uname -s)" != "Darwin" ] || ! command -v brew >/dev/null; then
	echo "skipped (needs macOS with Homebrew)"
	exit 0
fi

PREFIX="$(brew --prefix)"
SITE="$PREFIX/share/zsh/site-functions"

# Load the repo's rc the way a login shell does, but with $HOME and ZDOTDIR
# pointed at a throwaway directory: the copy stowed into the real $HOME is not
# what should be under test, and this way the shell's caches land in the temp
# directory rather than the machine's, which is what keeps `make qa` read-only.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ln -s "$ZSHRC" "$TMP/.zshrc"
# FPATH and HOMEBREW_PREFIX are scrubbed, and this is the whole point: both are
# exported by `brew shellenv`, so a test run from an already-configured shell
# inherits the very entry it is trying to prove the rc adds. With them left in,
# deleting the shellenv line from the rc still passes.
FPATH_OUT="$(env -u FPATH -u HOMEBREW_PREFIX -u HOMEBREW_CELLAR \
	-u HOMEBREW_REPOSITORY HOME="$TMP" ZDOTDIR="$TMP" \
	zsh -ic 'print -l -- $fpath' 2>/dev/null)"

echo "== the fpath entry every brew completion arrives on"
if grep -qxF "$SITE" <<<"$FPATH_OUT"; then ok "site-functions is on fpath"; else
	fail "site-functions is on fpath"
	echo "       $SITE is missing — brew shellenv either did not run or ran too late"
fi

echo
echo "== the setup recipes deliberately not followed"
# `stripe completion` prints three steps: mkdir ~/.stripe, add it to fpath, and
# run a second compinit. The first two would duplicate the formula's own
# _stripe; the third is what zsh-autocomplete's caveats tell you to remove.
if grep -q '\.stripe' <<<"$FPATH_OUT"; then
	fail "no hand-made completion directory on fpath"
	echo "       ~/.stripe is on fpath — the formula already ships _stripe"
else ok "no hand-made completion directory on fpath"; fi
# Comments stripped first — the block above this line in the rc explains the
# compinit policy at length, and counting prose would make the assertion drift
# with every edit to it.
check "the rc runs compinit only as the no-plugin fallback" \
	"$(grep -v '^[[:space:]]*#' "$ZSHRC" | grep -c 'compinit')" "1"

echo
echo "== stripe, the case this was written for"
# Only meaningful once `make apps` has run, so a machine without it says so
# rather than failing: the assertion above is what holds on a bare checkout.
if [ -e "$SITE/_stripe" ]; then
	ok "the Brewfile's stripe installed its completion"
	# The formula's _stripe is a four-line shim that locates the real script
	# relative to itself. If that ever resolves wrong, completion registers and
	# then silently returns nothing, which no fpath check would catch.
	check "and the shim's script is beside it" \
		"$(test -f "$SITE/stripe-completion.zsh" && echo yes || echo no)" "yes"
else
	echo "skip stripe not installed yet — run: make apps"
fi
grep -q 'stripe/stripe-cli/stripe' "$REPO/Brewfile" \
	&& ok "and the Brewfile is what installs it" \
	|| fail "and the Brewfile is what installs it"

echo
if [ "$FAILED" -eq 0 ]; then echo "all passed"; else echo "failures"; fi
exit "$FAILED"
