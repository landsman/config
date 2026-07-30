#!/usr/bin/env bash
# GUI apps for the Kubuntu boxes that the Brewfile cannot install, from the
# vendors' own apt repos. Run by `make brew` right after `brew bundle`, which
# finds this file as os/$(OS)/install-apps.sh — an OS without one is skipped,
# which is why macOS needs no guard here.
#
# Homebrew on Linux installs a cask only when that cask ships a Linux build,
# and almost no GUI app does. 1Password is the case in point: its cask is
# `depends_on macos`, its one artifact is a `.app`, and the `appimage` stanza
# that would cover Linux has nothing to point at, because 1Password publishes
# only `.deb`, `.rpm` and a tarball.
#
# Idempotent, and quiet when there is nothing to do: an app already installed
# is skipped before anything asks for root, so a re-run of `make brew` on an
# already-provisioned machine never prompts for a password.
#
#   bash os/ubuntu/install-apps.sh

set -euo pipefail

# 1Password signs twice: the repo, and the `.deb` itself with debsig. apt
# refuses to unpack the second without a policy naming the key under
# /etc/debsig/policies, so all four paths below derive from this one
# fingerprint — a rotation upstream is one line here.
ONEPASSWORD_KEY_URL="https://downloads.1password.com/linux/keys/1password.asc"
ONEPASSWORD_KEY_FPR="3FEF9748469ADBE15DA7CA80AC2D62742012EA22"
ONEPASSWORD_POL_URL="https://downloads.1password.com/linux/debian/debsig/1password.pol"

installed() {
	[ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null)" = "installed" ]
}

if installed 1password; then
	echo "== 1password: already installed"
	exit 0
fi

# Root is needed from here on. Re-exec rather than sudo each line, so the
# password is asked for once and the whole install shares one timestamp.
if [ "$EUID" -ne 0 ]; then
	echo "== 1password: missing, re-running as root"
	exec sudo -- "$BASH" "$0" "$@"
fi

ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
	amd64 | arm64) ;;
	*)
		echo "1Password publishes amd64 and arm64 only, this machine is $ARCH" >&2
		exit 1
		;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> [1/4] Fetching the signing key and checking its fingerprint"
curl -fsS "$ONEPASSWORD_KEY_URL" -o "$TMP/1password.asc"
# This key is about to be trusted to sign root-owned packages, so it is pinned
# rather than taken on faith: a MITM, or a hijacked bucket serving some other
# key, fails here instead of quietly signing whatever it likes afterwards.
GOT_FPR="$(gpg --show-keys --with-colons "$TMP/1password.asc" | awk -F: '/^fpr:/ { print $10; exit }')"
if [ "$GOT_FPR" != "$ONEPASSWORD_KEY_FPR" ]; then
	echo "1Password key fingerprint mismatch" >&2
	echo "  expected $ONEPASSWORD_KEY_FPR" >&2
	echo "  got      ${GOT_FPR:-<none>}" >&2
	echo "refusing to trust it - if the key really rotated, update the constant" >&2
	exit 1
fi
gpg --dearmor --yes --output "$TMP/1password.gpg" "$TMP/1password.asc"

echo "==> [2/4] Adding the apt repo ($ARCH)"
install -Dm644 "$TMP/1password.gpg" /usr/share/keyrings/1password-archive-keyring.gpg
install -Dm644 /dev/stdin /etc/apt/sources.list.d/1password.list <<EOF
deb [arch=$ARCH signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$ARCH stable main
EOF

# Last 16 of the fingerprint: what debsig calls the origin, and what it names
# both of its directories. Not a second secret, just the same key's short id.
KEY_ID="${ONEPASSWORD_KEY_FPR: -16}"
echo "==> [3/4] Installing the debsig policy for $KEY_ID"
curl -fsS "$ONEPASSWORD_POL_URL" -o "$TMP/1password.pol"
# The policy names the origin it expects. Checking it here turns a rotation
# into a readable error rather than a dpkg verification failure mid-unpack.
if ! grep -q "$KEY_ID" "$TMP/1password.pol"; then
	echo "the debsig policy does not mention $KEY_ID - upstream changed keys" >&2
	exit 1
fi
install -Dm644 "$TMP/1password.pol" "/etc/debsig/policies/$KEY_ID/1password.pol"
install -Dm644 "$TMP/1password.gpg" "/usr/share/debsig/keyrings/$KEY_ID/debsig.gpg"

echo "==> [4/4] Installing 1password"
apt-get update -qq
apt-get install -y 1password

# Not 1password-cli, though this repo now carries it: the CLI cask does ship a
# Linux build, so `op` comes from the Brewfile on every machine. Installing it
# from apt as well would put two of them on PATH.
echo
echo "Done. 'op' comes from the Brewfile - do not apt install 1password-cli."
