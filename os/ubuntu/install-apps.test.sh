#!/usr/bin/env bash
# Checks install-apps.sh without a Debian machine, and without installing
# anything: apt, dpkg, curl and gpg are replaced by stubs on PATH, and every
# root-owned path is redirected under a throwaway directory.
#
# The case that matters is the fingerprint pin. It is the one thing standing
# between a hijacked download and a key trusted to sign root-owned packages
# forever after, and a pin that silently passes everything is worse than no pin
# at all — so the mismatch case is asserted, not just the happy path.
#
#   bash os/ubuntu/install-apps.test.sh

# The stubs below are written to disk verbatim, so the unexpanded $1/$@ inside
# them are the point, not an oversight.
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/install-apps.sh"
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
# `--` because a pattern starting with one, like `--if-not-exists`, is otherwise
# read by grep as an option and the assertion silently fails on its own syntax.
contains() { if grep -qF -- "$3" "$2" 2>/dev/null; then ok "$1"; else
	fail "$1"
	echo "       $2 has no line containing: $3"
fi; }

# Build a stub PATH. INSTALLED lists packages dpkg-query should report, and
# FPR is what gpg claims every key's fingerprint is — set it to something the
# script does not expect and the pin should fire.
setup() {
	ROOT="$(mktemp -d)"
	BIN="$ROOT/bin"
	mkdir -p "$BIN"

	cat >"$BIN/dpkg-query" <<-STUB
		#!/usr/bin/env bash
		for p in \$INSTALLED; do [ "\$p" = "\${!#}" ] && { echo installed; exit 0; }; done
		exit 1
	STUB
	echo '#!/usr/bin/env bash
echo amd64' >"$BIN/dpkg"
	# Writes a placeholder for whatever it is asked to download.
	cat >"$BIN/curl" <<-'STUB'
		#!/usr/bin/env bash
		for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
		# The 1Password debsig policy is grepped for the key id, so echo one.
		case "$out" in *.pol) echo '<Origin id="AC2D62742012EA22"/>' >"$out" ;;
		# Flathub's key is one base64 line of the .flatpakrepo, and the script
		# decodes it before checking the pin — so it has to survive a round trip.
		*.flatpakrepo) printf 'Url=https://dl.flathub.org/repo/\nGPGKey=%s\n' \
			"$(printf key-material | base64)" >"$out" ;;
		*) echo "key-material" >"$out" ;; esac
	STUB
	# FLATPAK_PRESENT is the app ids `flatpak info` should claim are installed.
	# remote-add and install both land in files, so the case can assert that the
	# remote came from the verified local copy and not from the URL.
	cat >"$BIN/flatpak" <<-STUB
		#!/usr/bin/env bash
		case "\$1" in
		info) for a in \$FLATPAK_PRESENT; do [ "\$a" = "\$2" ] && exit 0; done; exit 1 ;;
		remote-add) shift; printf '%s\n' "\$@" >"$ROOT/flatpak-remote" ;;
		install) shift; printf '%s\n' "\$@" | grep -v '^-y\$' >"$ROOT/flatpak-installed" ;;
		esac
		exit 0
	STUB
	cat >"$BIN/gpg" <<-STUB
		#!/usr/bin/env bash
		case "\$1" in
		--show-keys) echo "fpr:::::::::\$FPR:" ;;
		--dearmor) for a in "\$@"; do [ "\$prev" = "--output" ] && echo dearmoured >"\$a"; prev="\$a"; done ;;
		esac
	STUB
	# Redirect every absolute destination under $ROOT instead of the real /.
	cat >"$BIN/install" <<-STUB
		#!/usr/bin/env bash
		args=(); for a in "\$@"; do case "\$a" in -*) ;; *) args+=("\$a") ;; esac; done
		src="\${args[0]}"; dest="$ROOT\${args[1]}"
		mkdir -p "\$(dirname "\$dest")" && cat "\$src" >"\$dest"
	STUB
	cat >"$BIN/apt-get" <<-STUB
		#!/usr/bin/env bash
		[ "\$1" = install ] && { shift; printf '%s\n' "\$@" | grep -v '^-y\$' >"$ROOT/apt-installed"; }
		exit 0
	STUB
	# The script re-execs itself under sudo. Run it in place, but report root
	# afterwards — `id` is stubbed too, since EUID is read-only in bash and a
	# sudo that does not actually elevate is the loop this guards against.
	echo '#!/usr/bin/env bash
[ "$1" = "--" ] && shift
FAKE_ROOT=1 exec "$@"' >"$BIN/sudo"
	echo '#!/usr/bin/env bash
[ -n "${FAKE_ROOT:-}" ] && echo 0 || echo 1000' >"$BIN/id"
	chmod +x "$BIN"/*
}

# The flatpak defaults to present, so every apt case below is unaffected by it
# and only the flatpak cases have to say anything about it.
run() { PATH="$BIN:$PATH" CODENAME=noble INSTALLED="$1" FPR="$2" \
	FLATPAK_PRESENT="${3-org.telegram.desktop}" bash "$SCRIPT" 2>&1; }

ALL="1password sublime-text dbeaver-ce docker-ce tailscale discord google-chrome-stable vlc libreoffice stripe"
# The list minus one app, so a case can be "only this one is missing".
without() { echo "$ALL" | tr ' ' '\n' | grep -vxF -e "${1:-}" -e "${2:-}" | tr '\n' ' '; }

echo "== every package already present"
setup
out="$(run "$ALL" deadbeef)"
check "exits before doing anything" "$?" "0"
check "says so" "$(echo "$out" | tail -1)" "== distro apps: all 11 installed"
if [ -f "$ROOT/apt-installed" ]; then fail "apt never ran"; else ok "apt never ran"; fi
rm -rf "$ROOT"

echo
echo "== nothing present, keys as expected"
setup
# Every stubbed key reports 1Password's fingerprint, so run 1Password alone:
# a shared stub cannot satisfy five different pins at once.
out="$(run "$(without 1password)" 3FEF9748469ADBE15DA7CA80AC2D62742012EA22)"
check "succeeds" "$?" "0"
contains "1password repo added" "$ROOT/etc/apt/sources.list.d/1password.list" \
	"https://downloads.1password.com/linux/debian/amd64 stable main"
contains "signed-by points at its own keyring" "$ROOT/etc/apt/sources.list.d/1password.list" \
	"signed-by=/usr/share/keyrings/1password-archive-keyring.gpg"
check "debsig keyring lands under the key id" \
	"$(test -f "$ROOT/usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg" && echo yes)" "yes"
check "debsig policy lands beside it" \
	"$(test -f "$ROOT/etc/debsig/policies/AC2D62742012EA22/1password.pol" && echo yes)" "yes"
check "installs exactly what was missing" "$(cat "$ROOT/apt-installed")" "1password"
rm -rf "$ROOT"

echo
echo "== a key whose fingerprint does not match"
setup
out="$(run "$(without 1password)" 0000000000000000000000000000000000000000)"
check "refuses to continue" "$?" "1"
case "$out" in *"fingerprint mismatch"*) ok "says why" ;; *) fail "says why" ;; esac
if [ -f "$ROOT/apt-installed" ]; then fail "installs nothing"; else ok "installs nothing"; fi
check "and adds no repo" "$(test -d "$ROOT/etc/apt" && echo yes || echo no)" "no"
rm -rf "$ROOT"

echo
echo "== discord, the one with no repo behind it"
setup
out="$(run "$(without discord)" deadbeef)"
check "succeeds" "$?" "0"
check "apt is handed the .deb itself, not a package name" \
	"$(basename "$(cat "$ROOT/apt-installed")")" "discord.deb"
check "and no apt repo is added for it" \
	"$(test -d "$ROOT/etc/apt" && echo yes || echo no)" "no"
rm -rf "$ROOT"

echo
echo "== chrome, whose repo is one key for all of Google"
setup
out="$(run "$(without google-chrome-stable)" EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796)"
check "succeeds" "$?" "0"
contains "chrome repo added" "$ROOT/etc/apt/sources.list.d/google-chrome.list" \
	"https://dl.google.com/linux/chrome/deb stable main"
contains "signed-by points at its own keyring" "$ROOT/etc/apt/sources.list.d/google-chrome.list" \
	"signed-by=/usr/share/keyrings/google-chrome-archive-keyring.gpg"
check "installs exactly what was missing" "$(cat "$ROOT/apt-installed")" "google-chrome-stable"
rm -rf "$ROOT"

echo
echo "== stripe, whose repo has one suite rather than a codename"
setup
out="$(run "$(without stripe)" 6681D7C3D103DAC65D79C25EDEEBD57F917C83E3)"
check "succeeds" "$?" "0"
# `stable` is the suite here, not the release codename the other repos take.
contains "stripe repo added" "$ROOT/etc/apt/sources.list.d/stripe.list" \
	"https://packages.stripe.dev/stripe-cli-debian-local stable main"
case "$(cat "$ROOT/etc/apt/sources.list.d/stripe.list")" in
*noble*) fail "does not paste the codename in" ;;
*) ok "does not paste the codename in" ;;
esac
check "installs exactly what was missing" "$(cat "$ROOT/apt-installed")" "stripe"
rm -rf "$ROOT"

echo
echo "== vlc and libreoffice, which the Ubuntu archive already has"
setup
out="$(run "$(without vlc libreoffice)" deadbeef)"
check "succeeds" "$?" "0"
check "both are installed" "$(tr '\n' ' ' <"$ROOT/apt-installed")" "vlc libreoffice "
# The point of this case: an archive package that grew a repo and a pinned key
# would be machinery bought for nothing, and nobody would notice from the outside.
check "and neither adds a repo or a key" \
	"$(test -d "$ROOT/etc/apt" -o -d "$ROOT/usr/share/keyrings" && echo yes || echo no)" "no"
rm -rf "$ROOT"

echo
echo "== telegram, the first flatpak"
setup
# Every apt package present, so the only thing to do is the flatpak — which is
# also the run that proves apt is not called with an empty argument list.
out="$(run "$ALL" 6E5C05D979C76DAF93C081354184DD4D907A7CAE "")"
check "succeeds" "$?" "0"
check "apt is asked for flatpak and the Discover backend, nothing else" \
	"$(tr '\n' ' ' <"$ROOT/apt-installed")" "flatpak plasma-discover-backend-flatpak "
check "the app is installed from flathub" \
	"$(tr '\n' ' ' <"$ROOT/flatpak-installed")" "flathub org.telegram.desktop "
contains "the remote is added, and only if it is not there already" \
	"$ROOT/flatpak-remote" "--if-not-exists"
# The point of this one: `remote-add <url>` would re-fetch the key and trust
# whatever came back, making the pin two lines above decorative.
case "$(cat "$ROOT/flatpak-remote")" in
*https://*) fail "from the checked local copy, not the URL" ;;
*.flatpakrepo) ok "from the checked local copy, not the URL" ;;
*) fail "from the checked local copy, not the URL" ;;
esac
rm -rf "$ROOT"

echo
echo "== flathub's key, when it is not the pinned one"
setup
out="$(run "$ALL" 0000000000000000000000000000000000000000 "")"
check "refuses to continue" "$?" "1"
case "$out" in *"flathub: key fingerprint mismatch"*) ok "says which key" ;;
*) fail "says which key" ;; esac
# apt already ran by then — flatpak itself is a legitimate install either way.
# What must not have happened is the remote being added or the app pulled from it.
if [ -f "$ROOT/flatpak-remote" ]; then fail "adds no remote"; else ok "adds no remote"; fi
if [ -f "$ROOT/flatpak-installed" ]; then fail "installs no app"; else ok "installs no app"; fi
rm -rf "$ROOT"

echo
if [ "$FAILED" -eq 0 ]; then echo "all passed"; else echo "failures"; fi
exit "$FAILED"
