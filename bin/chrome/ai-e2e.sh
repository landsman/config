#!/usr/bin/env bash
# The `ai-e2e` browser instance the agents drive: Chrome Canary on a data
# directory of its own. What it is for is shared/.agents/rules/browser-automation.md,
# why it is built this way is shared/.agents/caveats/browser-automation.md.
#
# usage: ai-e2e.sh start       start it, unless it is running
#        ai-e2e.sh device-id   the Claude extension's bridge id inside it
set -eu

dir="$HOME/.chrome-ai-e2e"

case "${1:-}" in
start)
	if pgrep -f "user-data-dir=$dir" >/dev/null; then echo running; exit 0; fi
	flags=(--user-data-dir="$dir" --restore-last-session)
	if [ "$(uname)" = Darwin ]; then
		# The built-in display as "left top width height", empty without a
		# second screen, so the window never opens on the one I work on.
		geometry=$(osascript -l JavaScript -e 'ObjC.import("AppKit"); var s = $.NSScreen.screens,
			main = s.objectAtIndex(0).frame, out = "";
			for (var i = 0; i < s.count; i++) { var sc = s.objectAtIndex(i), f = sc.frame;
				if (s.count > 1 && /Built-in/.test(ObjC.unwrap(sc.localizedName)))
					out = [f.origin.x, main.size.height - (f.origin.y + f.size.height),
						f.size.width, f.size.height].join(" "); }
			out')
		if [ -n "$geometry" ]; then
			read -r left top width height <<<"$geometry"
			flags+=(--window-position="$left,$top" --window-size="$width,$height")
		fi
		open -na "Google Chrome Canary" --args "${flags[@]}"
	else
		# Detached on purpose: the instance outlives the session that started it.
		# ponytail: no window position on Linux - Wayland ignores it; read the
		# eDP output of `xrandr --listmonitors` if an X11 box needs it.
		setsid -f google-chrome "${flags[@]}" >/dev/null 2>&1
	fi
	;;
device-id)
	# The id belongs to the data directory, so it is read from there every time.
	cat "$dir/Default/Local Extension Settings/fcoeoabgfenejglbffodgkkbkcdhcgfn/"* 2>/dev/null |
		LC_ALL=C grep -a -o 'bridgeDeviceId.\{0,12\}[0-9a-f-]\{36\}' |
		LC_ALL=C grep -a -o '[0-9a-f-]\{36\}' | tail -1 || true
	;;
*)
	sed -n '6,7p' "$0" >&2
	exit 2
	;;
esac
