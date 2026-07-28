#!/usr/bin/env bash
# Set the JVM options this repo owns in every JetBrains IDE config directory.
#
# The config file is co-owned with Toolbox, which rewrites it on every launch, so
# this patches the lines we own and leaves every other line exactly as it found
# them. README.md has the why — including why it is a script and not a stow package.
#
# usage: vmoptions.sh [--xmx MiB] [config-dir ...]   (dirs: for the test)
set -eu

# JetBrains ships 2048 MiB, which the indexer outgrows on any real project.
XMX=8192

usage() { echo "usage: ${0##*/} [--xmx MiB] [config-dir ...]" >&2; exit 2; }

while [ $# -gt 0 ]; do
	case $1 in
		# Validated because it is interpolated into the sed replacement below,
		# and because a bad -Xmx stops the JVM from starting at all — in a file
		# Toolbox also writes to, where that is not the obvious cause.
		--xmx) [ $# -ge 2 ] || usage
		       case $2 in ''|*[!0-9]*) usage ;; esac
		       XMX=$2; shift 2 ;;
		-*)    usage ;;
		*)     break ;;
	esac
done

[ $# -gt 0 ] || set -- \
	"$HOME/Library/Application Support/JetBrains" \
	"${XDG_CONFIG_HOME:-$HOME/.config}/JetBrains"

# Replace the line matching `anchor`, or append if the file has none. Never
# rewrites the file wholesale, so Toolbox's lines and the IDE's survive.
# `--` and -E on every grep: the patterns and values start with a dash, which BSD
# grep otherwise reads as options (`-Dawt.toolkit.name=…` becomes `--devices`),
# and -E keeps the anchor an ERE in both the grep and the sed it is reused in.
set_option() {
	local f=$1 anchor=$2 line=$3
	if grep -Eq -- "$anchor" "$f"; then
		grep -qxF -- "$line" "$f" || { sed -i.bak -E "s|$anchor.*|$line|" "$f"; rm -f "$f.bak"; }
	else
		# Toolbox leaves the file without a trailing newline, so the append would
		# otherwise land on the end of its last line. `$(tail -c1)` strips the
		# newline it reads, so an empty result means the file already ends in one.
		[ -z "$(tail -c1 "$f")" ] || printf '\n' >> "$f"
		printf '%s\n' "$line" >> "$f"
	fi
}

drop_option() {
	local f=$1 anchor=$2
	grep -Eq -- "$anchor" "$f" || return 0
	sed -i.bak -E "/$anchor/d" "$f"; rm -f "$f.bak"
}

found=0
for dir in "$@"; do
	for f in "$dir"/*/*.vmoptions; do
		# -L before -f, because -f follows the link: a stow package that moved
		# leaves a dangling symlink, and that is exactly what needs reporting.
		if [ -L "$f" ]; then
			echo "skipped, symlink into a stow package: $f"
			continue
		fi
		[ -f "$f" ] || continue

		set_option "$f" '^-Xmx' "-Xmx${XMX}m"

		# IDEA's native Wayland toolkit. Keyed on the running session rather than
		# on the OS package, because the T480 boots more than one of those — and
		# removed again under X11, since that is the same laptop on another boot.
		# Neither variable set means a tty or ssh, which says nothing either way,
		# so the line is left however the last graphical run left it.
		if [ -n "${WAYLAND_DISPLAY:-}" ]; then
			set_option "$f" '^-Dawt\.toolkit\.name=' '-Dawt.toolkit.name=WLToolkit'
		elif [ -n "${DISPLAY:-}" ]; then
			drop_option "$f" '^-Dawt\.toolkit\.name='
		fi

		found=$((found + 1))
		echo "$f"
		# -E, because BSD sed reads `\|` as a literal pipe rather than alternation
		sed -n -E '/^(-Xmx|-Dawt\.toolkit\.name=)/s/^/  /p' "$f"
	done
done

if [ "$found" -eq 0 ]; then
	echo "no JetBrains config directories - launch the IDE once first"
else
	echo "restart the IDE for this to take effect"
fi
