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
contains() { if grep -qF "$3" "$2" 2>/dev/null; then ok "$1"; else
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
		*) echo "key-material" >"$out" ;; esac
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

run() { PATH="$BIN:$PATH" CODENAME=noble INSTALLED="$1" FPR="$2" bash "$SCRIPT" 2>&1; }

echo "== every package already present"
setup
out="$(run "1password sublime-text dbeaver-ce docker-ce tailscale" deadbeef)"
check "exits before doing anything" "$?" "0"
check "says so" "$(echo "$out" | tail -1)" "== distro apps: all 5 installed"
if [ -f "$ROOT/apt-installed" ]; then fail "apt never ran"; else ok "apt never ran"; fi
rm -rf "$ROOT"

echo
echo "== nothing present, keys as expected"
setup
# Every stubbed key reports 1Password's fingerprint, so run 1Password alone:
# a shared stub cannot satisfy five different pins at once.
out="$(run "sublime-text dbeaver-ce docker-ce tailscale" 3FEF9748469ADBE15DA7CA80AC2D62742012EA22)"
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
out="$(run "sublime-text dbeaver-ce docker-ce tailscale" 0000000000000000000000000000000000000000)"
check "refuses to continue" "$?" "1"
case "$out" in *"fingerprint mismatch"*) ok "says why" ;; *) fail "says why" ;; esac
if [ -f "$ROOT/apt-installed" ]; then fail "installs nothing"; else ok "installs nothing"; fi
check "and adds no repo" "$(test -d "$ROOT/etc/apt" && echo yes || echo no)" "no"
rm -rf "$ROOT"

echo
if [ "$FAILED" -eq 0 ]; then echo "all passed"; else echo "failures"; fi
exit "$FAILED"
