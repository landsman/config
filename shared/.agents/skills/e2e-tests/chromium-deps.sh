#!/usr/bin/env bash
# What a Chromium-only Playwright run needs from the OS, measured in a throwaway
# container of the Forgejo runner image. The skill's package counts and its
# advice on libgtk-3-0 and libxcursor1 come from this output; re-run it on a
# Playwright bump.
#
#   chromium-deps.sh
#   PLAYWRIGHT=1.64.0 chromium-deps.sh
#
# Pinned: the image by digest, the platform, the Playwright version. Not pinned:
# the apt mirror, so package counts and sizes can drift a little between runs.
# No cache, on purpose: once a browser passes Playwright's host check, a
# DEPENDENCIES_VALIDATED file in its directory skips the check for 30 days, so
# a reused browser directory would hide the result.
set -euo pipefail

if [ "${1:-}" != --inside ]; then
	IMAGE=${IMAGE:-docker.gitea.com/runner-images:ubuntu-22.04@sha256:3ec7241e9701767f32992cc0e1d009c065426a3bacf748d90d01162f58e39f7e}
	PLATFORM=${PLATFORM:-linux/amd64} # the Forgejo runners are amd64
	PLAYWRIGHT=${PLAYWRIGHT:-1.63.0}
	echo "image:      $IMAGE"
	echo "platform:   $PLATFORM"
	echo "playwright: $PLAYWRIGHT"
	self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
	# Two containers: the bare install-deps would otherwise leave Chromium's
	# libraries behind for the rest to find.
	for mode in bare chromium; do
		docker run --rm --platform "$PLATFORM" -v "$self:/chromium-deps.sh:ro" \
			"$IMAGE" bash /chromium-deps.sh --inside "$PLAYWRIGHT" "$mode"
	done
	exit
fi

# From here on inside the container. No -e: a failing step is a finding, and
# the next one still runs.
set +e
export DEBIAN_FRONTEND=noninteractive
cd "$(mktemp -d)" && npm init -y >/dev/null
npm install --silent --no-audit --no-fund "playwright@$2" >/dev/null || exit 1
echo
echo "date:       $(date -u +%FT%TZ), node $(node --version), $(uname -m)"
browsers=~/.cache/ms-playwright

if [ "$3" = bare ]; then
	echo
	echo "## 0. bare install-deps, every browser's libraries"
	npx --no-install playwright install-deps >deps.log 2>&1
	grep -E 'newly installed|^Need to get' deps.log
	exit
fi

# What Playwright's "missing dependencies" box names: apt packages, or bare
# libraries when it cannot map them.
warned() {
	grep -q 'missing dependencies' "$1" || {
		echo none
		return
	}
	sed -n '/missing dependencies/,/╚/p' "$1" |
		grep -oE '\b(lib[a-z0-9._+-]*|gstreamer[a-z0-9.+-]*|fonts-[a-z0-9-]+|xvfb)\b' |
		grep -vx libraries | sort -u | tr '\n' ' '
	echo
}

# The second reading: ldd over every binary and library in a browser's builds,
# whichever directory they unpacked into. The builds' own directories go on
# LD_LIBRARY_PATH, as Playwright's check does, so a library a browser ships
# with itself does not count as missing.
notfound() {
	local dirs out
	dirs=$(find "$browsers"/"$1"* -type d | paste -sd: -)
	out=$(find "$browsers"/"$1"* -type f \( -perm -u+x -o -name '*.so*' \) \
		-exec env LD_LIBRARY_PATH="$dirs" ldd {} + 2>/dev/null |
		awk '$2 == "=>" && $3 == "not" {print $1}' | sort -u | tr '\n' ' ')
	echo "${out:-none}"
}

echo
echo "## 1. install-deps chromium"
npx --no-install playwright install-deps chromium >deps.log 2>&1
grep -E 'newly installed|^Need to get' deps.log

echo
echo "## 2. install chromium"
npx --no-install playwright install chromium >install.log 2>&1
echo "builds:           $(cd "$browsers" && du -sm -- */ | awk '{printf "%s %s MB, ", $2, $1}')"
echo "layout:           $(cd "$browsers" && find . -mindepth 2 -maxdepth 2 -type d | sort | tr '\n' ' ')"
echo "playwright warns: $(warned install.log)"
echo "ldd not found:    $(notfound chromium)"

echo
echo "## 3. headless launch"
node -e '
  require("playwright").chromium.launch().then(async b => {
    const p = await b.newPage();
    await p.setContent("<p>rendered</p>");
    console.log(await p.textContent("p"));
    await b.close();
  });' >launch.log 2>&1
echo "exit $?:           $(head -1 launch.log)"
echo "playwright warns: $(warned launch.log)"

echo
echo "## 4. bare install, what Playwright Java runs on every Playwright.create()"
npx --no-install playwright install >bare.log 2>&1
echo "playwright warns: $(warned bare.log)"
echo "ldd not found, firefox: $(notfound firefox)"
echo "ldd not found, webkit:  $(notfound webkit)"

echo
echo "## 5. apt-get install libgtk-3-0 libxcursor1, then bare install again"
apt-get install -y --no-install-recommends libgtk-3-0 libxcursor1 >gtk.log 2>&1
grep -E 'newly installed|^Need to get' gtk.log
npx --no-install playwright install >bare2.log 2>&1
echo "playwright warns: $(warned bare2.log)"
echo "ldd not found, firefox: $(notfound firefox)"
echo "ldd not found, webkit:  $(notfound webkit)"
