#!/usr/bin/env bash
# GUI apps for the Kubuntu boxes that the Brewfile cannot install, from the
# vendors' own apt repos. Run by `make apps` right after `brew bundle`, which
# finds this file as os/$(OS)/install-apps.sh — an OS without one is skipped,
# which is why macOS needs no guard here.
#
# Homebrew on Linux installs a cask only when that cask ships a Linux build,
# and almost no GUI app does, so the whole GUI half of the Brewfile sits behind
# `if OS.mac?` and the Linux equivalents live here instead. Which apps are and
# are not reachable this way — including the ones with no Linux build at all —
# is written down in the README next to this file.
#
# Idempotent, and quiet when there is nothing to do: already-installed apps are
# skipped before anything asks for root, so a re-run of `make apps` on a
# provisioned machine neither reinstalls nor prompts for a password.
#
#   bash os/ubuntu/install-apps.sh

set -euo pipefail

# Every key below is pinned. Fetching a key over TLS and trusting whatever comes
# back is the usual vendor instruction, but that key then authenticates
# root-owned packages forever after — pinning turns a hijacked bucket or a
# corporate TLS intercept into a failed install rather than a silent one.
# Cross-check a fingerprint against the vendor's docs before changing it.
ONEPASSWORD_KEY_URL="https://downloads.1password.com/linux/keys/1password.asc"
ONEPASSWORD_KEY_FPR="3FEF9748469ADBE15DA7CA80AC2D62742012EA22"
ONEPASSWORD_POL_URL="https://downloads.1password.com/linux/debian/debsig/1password.pol"
SUBLIME_KEY_URL="https://download.sublimetext.com/sublimehq-pub.gpg"
SUBLIME_KEY_FPR="1EDDE2CDFC025D17F6DA9EC0ADAE6AD28A8F901A"
DBEAVER_KEY_URL="https://dbeaver.io/debs/dbeaver.gpg.key"
DBEAVER_KEY_FPR="BDFB19F681514B43875D16FA132C13A8A330F403"
DOCKER_KEY_URL="https://download.docker.com/linux/ubuntu/gpg"
DOCKER_KEY_FPR="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"
TAILSCALE_KEY_URL="https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg"
TAILSCALE_KEY_FPR="2596A99EAAB33821893C0A79458CA832957F5868"

# Discord is the exception to all of the above, deliberately: it publishes no
# apt repo, no checksum and no signature — the URL below redirects to whatever
# the current .deb is, so there is nothing stable to pin even if we wanted to.
# TLS is the only thing vouching for this one. See the README.
DISCORD_DEB_URL="https://discord.com/api/download?platform=linux&format=deb"

# The package each app is identified by. Docker pulls in its plugins too, but
# docker-ce is what "is Docker here?" comes down to.
PACKAGES=(1password sublime-text dbeaver-ce docker-ce tailscale discord)

installed() {
	[ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null)" = "installed" ]
}

MISSING=()
for pkg in "${PACKAGES[@]}"; do
	installed "$pkg" || MISSING+=("$pkg")
done

if [ ${#MISSING[@]} -eq 0 ]; then
	echo "== distro apps: all ${#PACKAGES[@]} installed"
	exit 0
fi

echo "== distro apps: missing ${MISSING[*]}"

# Root is needed from here on. Re-exec rather than sudo per line, so the
# password is asked for once and the whole run shares one timestamp. The marker
# makes that exactly one attempt: a sudo that returns without root would
# otherwise put this script into an endless re-exec of itself.
if [ "$(id -u)" -ne 0 ]; then
	if [ -n "${INSTALL_APPS_ELEVATED:-}" ]; then
		echo "sudo returned without root - giving up rather than looping" >&2
		exit 1
	fi
	exec sudo -- env INSTALL_APPS_ELEVATED=1 "$BASH" "$0" "$@"
fi

ARCH="$(dpkg --print-architecture)"
# Kubuntu sets UBUNTU_CODENAME to the Ubuntu base, which is what these vendors
# publish against; VERSION_CODENAME is the fallback for plain Debian. Both are
# overridable from the environment, for the gap after a release where a vendor
# has not published the new codename yet — and so the tests can pin them.
# shellcheck disable=SC1091 # /etc/os-release is generated, not in the repo
CODENAME="${CODENAME:-$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Fetch a signing key, refuse it unless the fingerprint matches, and leave the
# dearmoured copy at $TMP/<name>.gpg for the caller.
fetch_key() {
	local name="$1" url="$2" want="$3" got
	curl -fsS "$url" -o "$TMP/$name.key"
	got="$(gpg --show-keys --with-colons "$TMP/$name.key" | awk -F: '/^fpr:/ { print $10; exit }')"
	if [ "$got" != "$want" ]; then
		echo "$name: key fingerprint mismatch" >&2
		echo "  expected $want" >&2
		echo "  got      ${got:-<none>}" >&2
		echo "refusing to trust it - verify against the vendor's docs first" >&2
		exit 1
	fi
	gpg --dearmor --yes --output "$TMP/$name.gpg" "$TMP/$name.key"
}

# Install the keyring and the sources list for one vendor. `suite` is a
# codename for a normal repo, or a path ending in / for a flat one, in which
# case `components` is empty — that is plain apt syntax, not a special case.
add_repo() {
	local name="$1" url="$2" fpr="$3" base="$4" suite="$5" components="${6:-}"
	local keyring="/usr/share/keyrings/$name-archive-keyring.gpg"
	fetch_key "$name" "$url" "$fpr"
	install -Dm644 "$TMP/$name.gpg" "$keyring"
	install -Dm644 /dev/stdin "/etc/apt/sources.list.d/$name.list" <<-EOF
		deb [arch=$ARCH signed-by=$keyring] $base $suite $components
	EOF
}

# 1Password signs twice: the repo, and the .deb itself with debsig. apt refuses
# to unpack the second without a policy naming the key under
# /etc/debsig/policies, so this one needs two extra files the others do not.
setup_1password() {
	add_repo 1password "$ONEPASSWORD_KEY_URL" "$ONEPASSWORD_KEY_FPR" \
		"https://downloads.1password.com/linux/debian/$ARCH" stable main
	# Last 16 of the fingerprint: what debsig calls the origin, and what it
	# names both of its directories. Not a second secret, the same key's id.
	local key_id="${ONEPASSWORD_KEY_FPR: -16}"
	curl -fsS "$ONEPASSWORD_POL_URL" -o "$TMP/1password.pol"
	# The policy names the origin it expects. Checking it turns a key rotation
	# into a readable error instead of a dpkg failure mid-unpack.
	if ! grep -q "$key_id" "$TMP/1password.pol"; then
		echo "1password: debsig policy does not mention $key_id - upstream rotated keys" >&2
		exit 1
	fi
	install -Dm644 "$TMP/1password.pol" "/etc/debsig/policies/$key_id/1password.pol"
	install -Dm644 "$TMP/1password.gpg" "/usr/share/debsig/keyrings/$key_id/debsig.gpg"
}

INSTALL=()
for pkg in "${MISSING[@]}"; do
	echo "==> Configuring $pkg"
	case "$pkg" in
	1password)
		setup_1password
		INSTALL+=(1password)
		;;
	sublime-text)
		add_repo sublime-text "$SUBLIME_KEY_URL" "$SUBLIME_KEY_FPR" \
			https://download.sublimetext.com/ apt/stable/
		INSTALL+=(sublime-text)
		;;
	dbeaver-ce)
		add_repo dbeaver "$DBEAVER_KEY_URL" "$DBEAVER_KEY_FPR" \
			https://dbeaver.io/debs/dbeaver-ce /
		INSTALL+=(dbeaver-ce)
		;;
	docker-ce)
		add_repo docker "$DOCKER_KEY_URL" "$DOCKER_KEY_FPR" \
			https://download.docker.com/linux/ubuntu "$CODENAME" stable
		# The engine alone is not usable: the CLI, the runtime and the two
		# plugins `docker build`/`docker compose` shell out to are separate
		# packages in this repo.
		INSTALL+=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
		;;
	tailscale)
		add_repo tailscale "$TAILSCALE_KEY_URL" "$TAILSCALE_KEY_FPR" \
			https://pkgs.tailscale.com/stable/ubuntu "$CODENAME" main
		INSTALL+=(tailscale)
		;;
	discord)
		# No repo to add, so the .deb itself is the download and apt is handed a
		# path instead of a name — it resolves the dependencies either way.
		curl -fsSL "$DISCORD_DEB_URL" -o "$TMP/discord.deb"
		INSTALL+=("$TMP/discord.deb")
		;;
	esac
done

echo "==> Installing ${INSTALL[*]}"
apt-get update -qq
apt-get install -y "${INSTALL[@]}"

echo
echo "Done. Three things this script deliberately leaves to you:"
echo "  - docker: 'usermod -aG docker \$USER' is what lets lazydocker talk to"
echo "    the socket without sudo, and it is root-equivalent - your call."
echo "  - tailscale: installed but not joined, run 'sudo tailscale up'."
echo "  - discord: no apt repo backs that .deb, so apt will never update it."
echo "    'sudo apt-get remove discord' and re-run this to get the current one,"
echo "    which is what an outdated client refusing to connect is telling you."
