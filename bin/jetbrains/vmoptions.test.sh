#!/usr/bin/env bash
# Self-check for ./vmoptions.sh. No framework: it builds fake config directories,
# runs the real script against them, and asserts on the files it produced.
set -eu

script="$(cd "$(dirname "$0")" && pwd)/vmoptions.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

# The session variables decide what the script does, so the caller's must not
# leak in — otherwise this suite fails on the T480, the one machine the Wayland
# flag exists for, while passing on a headless CI runner that has neither.
# HOME is redirected for the same reason: every case below passes explicit
# directories, but one that forgets would patch the developer's real IDE config.
unset WAYLAND_DISPLAY DISPLAY
export HOME=$tmp

# What Toolbox actually leaves behind — the token and port path are per machine,
# and are the reason this file is patched instead of stowed.
toolbox_lines='-Dide.managed.by.toolbox=/Applications/JetBrains Toolbox.app/Contents/MacOS/jetbrains-toolbox
-Dtoolbox.notification.token=00000000-0000-0000-0000-000000000000
-Dtoolbox.notification.portFile=/home/placeholder/.cache/JetBrains/Toolbox/ports/00000000.port'

# make_config <dir> <version> [extra lines...] -> echoes the vmoptions path
make_config() {
	local root=$1 version=$2; shift 2
	mkdir -p "$root/$version"
	{ printf '%s\n' "$toolbox_lines"; [ $# -eq 0 ] || printf '%s\n' "$@"; } > "$root/$version/idea.vmoptions"
	echo "$root/$version/idea.vmoptions"
}

check() {  # check <name> <expected> <actual>
	if [ "$2" = "$3" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1"; echo "  expected: $2"; echo "  actual:   $3"; fails=$((fails + 1))
	fi
}

# Both platform paths are swept, so one run is correct on macOS and on Linux.
mac="$tmp/Library/Application Support/JetBrains"
linux="$tmp/.config/JetBrains"
mac_file=$(make_config "$mac" IntelliJIdea2026.2 '-Xmx2048m')
linux_file=$(make_config "$linux" IntelliJIdea2026.2 '-Xmx1966m')

# A file that predates any -Xmx line at all, written the way Toolbox actually
# writes it: no trailing newline, so a naive append lands on the last line.
bare_file=$(make_config "$mac" WebStorm2026.1)
printf '%s' "$toolbox_lines" > "$bare_file"

# A leftover stow symlink: writing through it would land in git.
outside="$tmp/in-the-repo.vmoptions"
printf -- '-Xmx1966m\n' > "$outside"
mkdir -p "$mac/IntelliJIdea2025.2"
ln -s "$outside" "$mac/IntelliJIdea2025.2/idea64.vmoptions"

out=$("$script" --xmx 8192 "$mac" "$linux")

check "macOS path patched"   '-Xmx8192m' "$(grep '^-Xmx' "$mac_file")"
check "linux path patched"   '-Xmx8192m' "$(grep '^-Xmx' "$linux_file")"
check "-Xmx appended when absent" '-Xmx8192m' "$(grep '^-Xmx' "$bare_file")"
check "last Toolbox line intact"  "$toolbox_lines" "$(grep '^-D' "$bare_file")"
check "file ends in a newline"    '' "$(tail -c1 "$bare_file")"
check "exactly one -Xmx line" '1' "$(grep -c '^-Xmx' "$mac_file")"
check "Toolbox lines untouched" "$toolbox_lines" "$(grep '^-D' "$mac_file")"
check "symlink left alone"   '-Xmx1966m' "$(cat "$outside")"
case $out in *"skipped, symlink"*) echo "ok   symlink reported";;
	*) echo "FAIL symlink reported"; fails=$((fails + 1));; esac

# The run reports what it set, one indented line per option it owns. Asserted
# because the summary is a `sed` script of its own and can rot independently.
check "reports each file it touched" '3' "$(grep -c '/idea\.vmoptions$' <<<"$out")"
check "reports the option it set"    '3' "$(grep -c '^  -Xmx8192m$' <<<"$out")"

before=$(cat "$mac_file")
"$script" --xmx 8192 "$mac" "$linux" >/dev/null
check "idempotent" "$before" "$(cat "$mac_file")"

# Wayland: added in a Wayland session, never twice, taken away again under X11,
# and left alone from a tty where neither variable says anything.
check "no toolkit line off Wayland" '' "$(grep '^-Dawt' "$mac_file" || true)"
WAYLAND_DISPLAY=wayland-1 "$script" --xmx 8192 "$linux" >/dev/null
WAYLAND_DISPLAY=wayland-1 "$script" --xmx 8192 "$linux" >/dev/null
check "toolkit line on Wayland" '1' "$(grep -c '^-Dawt\.toolkit\.name=WLToolkit$' "$linux_file")"

"$script" --xmx 8192 "$linux" >/dev/null   # a tty: neither variable is set
check "toolkit line kept from a tty" '1' "$(grep -c '^-Dawt\.toolkit\.name=' "$linux_file")"
DISPLAY=:0 "$script" --xmx 8192 "$linux" >/dev/null
check "toolkit line dropped under X11" '0' "$(grep -c '^-Dawt' "$linux_file" || true)"
check "X11 run kept the rest"  "$toolbox_lines" "$(grep '^-D' "$linux_file")"

# A bad --xmx reaches sed as a replacement, so it is rejected before that.
check "non-numeric --xmx rejected" '2' "$("$script" --xmx lots "$linux" >/dev/null 2>&1; echo $?)"
check "--xmx with no value rejected" '2' "$("$script" --xmx >/dev/null 2>&1; echo $?)"
check "heap survived the rejects" '-Xmx8192m' "$(grep '^-Xmx' "$linux_file")"

# A dangling stow symlink is the case the skip message exists for.
ln -s "$tmp/gone.vmoptions" "$mac/IntelliJIdea2025.2/dangling.vmoptions"
case $("$script" "$mac") in *"skipped, symlink into a stow package"*"dangling"*) echo "ok   dangling symlink reported";;
	*) echo "FAIL dangling symlink reported"; fails=$((fails + 1));; esac

# A machine with no IDE installed is not an error.
mkdir -p "$tmp/empty"
case $("$script" "$tmp/empty") in *"no JetBrains config directories"*) echo "ok   empty machine";;
	*) echo "FAIL empty machine"; fails=$((fails + 1));; esac

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
