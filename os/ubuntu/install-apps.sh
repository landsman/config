#!/usr/bin/env bash
# Apps for the Kubuntu boxes that the Brewfile cannot install — the GUI ones,
# plus the odd CLI whose formula is macOS-only — from the vendors' own apt
# repos. Run by `make apps` right after `brew bundle`, which
# finds this file as os/$(OS)/install-apps.sh — an OS without one is skipped,
# which is why macOS needs no guard here.
#
# Homebrew on Linux installs a cask only when that cask ships a Linux build,
# and almost no GUI app does, so the whole GUI half of the Brewfile sits behind
# `if OS.mac?` and the Linux equivalents live here instead. Which apps are and
# are not reachable this way — including the ones with no Linux build at all —
# is written down in the README next to this file.
#
# Apt is the channel; Flathub is the exception, for an app whose Linux build is
# real but reaches nobody through apt. Deliberately not a general escape hatch —
# an app goes there only once apt has been ruled out and the README says why.
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
STRIPE_KEY_URL="https://packages.stripe.dev/api/security/keypair/stripe-cli-gpg/public"
STRIPE_KEY_FPR="6681D7C3D103DAC65D79C25EDEEBD57F917C83E3"
# One key signs every Google Linux repo, Chrome's included. The subkeys rotate
# yearly and the primary is what apt verifies against, so the primary is pinned.
GOOGLE_KEY_URL="https://dl.google.com/linux/linux_signing_key.pub"
GOOGLE_KEY_FPR="EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796"
# Flathub ships its key inside the .flatpakrepo rather than as a download of its
# own, so this pin is checked against what that file carries. Same primary key
# as the standalone https://dl.flathub.org/repo/flathub.gpg, which is how it was
# cross-checked; the subkey under it rotates, the primary is what signs.
FLATHUB_REPO_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"
FLATHUB_KEY_FPR="6E5C05D979C76DAF93C081354184DD4D907A7CAE"

# The package each app is identified by. Docker pulls in its plugins too, but
# docker-ce is what "is Docker here?" comes down to. Two of them need no vendor
# repo at all — Ubuntu ships them — but they belong in the same list, because
# what this script answers is "are the apps this repo names here yet".
PACKAGES=(1password sublime-text dbeaver-ce docker-ce tailscale discord
	google-chrome-stable vlc libreoffice stripe)

# The apps that come from Flathub instead, by app id. Telegram is the only one
# and the reason this half exists at all: it was dropped from the Ubuntu archive
# after jammy, and upstream publishes a tarball, a Snap and a Flatpak but no apt
# repo — so there is nothing for the machinery above to hang an app on.
FLATPAKS=(org.telegram.desktop)

installed() {
	[ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null)" = "installed" ]
}

MISSING=()
for pkg in "${PACKAGES[@]}"; do
	installed "$pkg" || MISSING+=("$pkg")
done

# Swallows "command not found" as well as "not installed", which is what a
# machine without flatpak yet should read as: the app is missing either way.
MISSING_FLATPAK=()
for app in "${FLATPAKS[@]}"; do
	flatpak info "$app" >/dev/null 2>&1 || MISSING_FLATPAK+=("$app")
done

if [ ${#MISSING[@]} -eq 0 ] && [ ${#MISSING_FLATPAK[@]} -eq 0 ]; then
	echo "== distro apps: all $(( ${#PACKAGES[@]} + ${#FLATPAKS[@]} )) installed"
	exit 0
fi

# Two lines rather than one joined list: either array can be empty here, and an
# empty one is not expandable under `set -u` on the bash the tests run under.
[ ${#MISSING[@]} -eq 0 ] || echo "== distro apps: missing ${MISSING[*]}"
[ ${#MISSING_FLATPAK[@]} -eq 0 ] || echo "== flatpaks: missing ${MISSING_FLATPAK[*]}"

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

# The pin itself: a key file is trusted only when its primary fingerprint is the
# one written down at the top. Its own function because Flathub's key arrives
# inside the .flatpakrepo rather than as a download, so apt and flatpak reach
# this check by different routes — and one copy of it is what keeps the two
# channels honest about the same thing.
check_fpr() {
	local name="$1" file="$2" want="$3" got
	got="$(gpg --show-keys --with-colons "$file" | awk -F: '/^fpr:/ { print $10; exit }')"
	if [ "$got" != "$want" ]; then
		echo "$name: key fingerprint mismatch" >&2
		echo "  expected $want" >&2
		echo "  got      ${got:-<none>}" >&2
		echo "refusing to trust it - verify against the vendor's docs first" >&2
		exit 1
	fi
}

# Fetch a signing key, refuse it unless the fingerprint matches, and leave the
# dearmoured copy at $TMP/<name>.gpg for the caller.
fetch_key() {
	local name="$1" url="$2" want="$3"
	curl -fsS "$url" -o "$TMP/$name.key"
	check_fpr "$name" "$TMP/$name.key" "$want"
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
# `${a[@]+"${a[@]}"}` rather than a plain `"${a[@]}"`: MISSING is legitimately
# empty on a run whose only missing app is the flatpak, and an empty array is
# not expandable under `set -u` on bash 3.2 — which is the bash the tests run
# under on macOS. The long form still quotes each element.
for pkg in ${MISSING[@]+"${MISSING[@]}"}; do
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
	stripe)
		# One codename-less suite for every release, which is why `stable` here
		# is not $CODENAME. The Brewfile installs this one on the Mac; its tap
		# formula is macOS-only, so Linux comes through apt instead.
		add_repo stripe "$STRIPE_KEY_URL" "$STRIPE_KEY_FPR" \
			https://packages.stripe.dev/stripe-cli-debian-local stable main
		INSTALL+=(stripe)
		;;
	google-chrome-stable)
		add_repo google-chrome "$GOOGLE_KEY_URL" "$GOOGLE_KEY_FPR" \
			https://dl.google.com/linux/chrome/deb stable main
		INSTALL+=(google-chrome-stable)
		;;
	vlc | libreoffice)
		# In the Ubuntu archive, so there is nothing to configure: no repo, no
		# key, and the distro's own signing already covers it. Listed anyway, so
		# that a fresh machine gets them from `make apps` like everything else.
		INSTALL+=("$pkg")
		;;
	discord)
		# The deliberate exception to the pinning above: no apt repo, no
		# checksum, no signature, and this URL redirects to whatever the current
		# .deb is — so there is nothing stable to pin and TLS is all that vouches
		# for it. No repo to add either, so the .deb itself is the download and
		# apt is handed a path instead of a name; it resolves the dependencies
		# either way. The README says what that costs.
		curl -fsSL "https://discord.com/api/download?platform=linux&format=deb" \
			-o "$TMP/discord.deb"
		INSTALL+=("$TMP/discord.deb")
		;;
	esac
done

# Flatpak is not on a Kubuntu install by default, and neither is the Discover
# backend — without that one a flatpak updates only from the command line, which
# is the same trap the Discord .deb is already in. Both come from the archive.
if [ ${#MISSING_FLATPAK[@]} -gt 0 ] && ! installed flatpak; then
	echo "==> Configuring flatpak"
	INSTALL+=(flatpak plasma-discover-backend-flatpak)
fi

# Guarded, because a run whose only missing app is a flatpak leaves this empty
# and `apt-get install` with no arguments is an error, not a no-op.
if [ ${#INSTALL[@]} -gt 0 ]; then
	echo "==> Installing ${INSTALL[*]}"
	apt-get update -qq
	apt-get install -y "${INSTALL[@]}"
fi

if [ ${#MISSING_FLATPAK[@]} -gt 0 ]; then
	echo "==> Configuring flathub"
	curl -fsS "$FLATHUB_REPO_URL" -o "$TMP/flathub.flatpakrepo"
	# The key is one base64 line of that ini file. Pull it out and hold it to the
	# same pin as every apt key here: once the remote is added it authenticates
	# every app and every update from it, which is the concern that made the
	# fingerprints above worth pinning in the first place.
	sed -n 's/^GPGKey=//p' "$TMP/flathub.flatpakrepo" | base64 -d >"$TMP/flathub.gpg"
	check_fpr flathub "$TMP/flathub.gpg" "$FLATHUB_KEY_FPR"
	# Added from the verified local file rather than from the URL, so the key
	# that ends up trusted is the one just checked and not a second fetch of it.
	flatpak remote-add --if-not-exists flathub "$TMP/flathub.flatpakrepo"
	echo "==> Installing ${MISSING_FLATPAK[*]}"
	flatpak install -y flathub "${MISSING_FLATPAK[@]}"
fi

echo
echo "Done. Four things this script deliberately leaves to you:"
echo "  - docker: 'usermod -aG docker \$USER' is what lets lazydocker talk to"
echo "    the socket without sudo, and it is root-equivalent - your call."
echo "  - tailscale: installed but not joined, run 'sudo tailscale up'."
echo "  - discord: no apt repo backs that .deb, so apt will never update it."
echo "    'sudo apt-get remove discord' and re-run this to get the current one,"
echo "    which is what an outdated client refusing to connect is telling you."
echo "  - telegram: a flatpak, and one only reaches the app menu once the session"
echo "    has read /etc/profile.d/flatpak.sh - log out and back in if it is not"
echo "    there. 'flatpak run org.telegram.desktop' works right now either way."
