#!/usr/bin/env bash
# Records a call (Google Meet or any other) with OBS without touching its audio:
# what the Mac plays is tapped through ScreenCaptureKit and the mic is read as
# it is, so the call app keeps its own devices and nobody hears a difference.
# The whole Mac rather than one app, so it works whatever the call runs in;
# mute notifications during a call, they get recorded too.
#
# OBS is driven over its built-in websocket (obsws.py); its profiles and
# scenes are files in config/. Tracks: 1 = both mixed, 2 = the call, 3 = my mic;
# a player plays the first. In the scenes, "mixers" is a bitmask of the tracks
# a source feeds: 3 = 1+2, 5 = 1+3.
#
# usage: record.sh setup                  install OBS and set it up (quits OBS first)
#        record.sh start [audio|video]    asks which when not given, Enter = audio
#        record.sh stop [name]            stop, ask for a name when not given (Enter = the
#                                         time), save to ~/Recordings, print the path
#        record.sh mode <answer>          the answer to "audio or video?", as audio|video
#        record.sh slug <name>            a name as it goes into the file name
#        record.sh save <mode> <raw> <dir> [name]  convert OBS's raw file into
#                                         <dir>/YYYYMMDD-<name>.m4a|mp4, print the path
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
conf="$HOME/Library/Application Support/obs-studio"
out="${RECORDINGS_DIR:-$HOME/Recordings}"
obs_pattern="OBS.app/Contents/MacOS/OBS$"

ws() { python3 "$here/obsws.py" "$@"; }

mode() {
	case "${1:-}" in
	"" | a | audio) echo audio ;;
	v | video) echo video ;;
	*) echo "audio or video, not '$1'" >&2 && return 1 ;;
	esac
}

# "Porada s Šárkou" -> porada-s-sarkou. Python, as macOS's iconv mangles the
# accents ("S'ar'aou").
slug() {
	python3 -c 'import re, sys, unicodedata
s = unicodedata.normalize("NFKD", sys.argv[1]).encode("ascii", "ignore").decode().lower()
print(re.sub(r"[^a-z0-9]+", "-", s).strip("-"))' "$1"
}

save() {
	local m=$1 raw=$2 dir=$3 name stamp base ext=m4a dst i=2
	local -a map=(-map 0:a)
	stamp=$(basename "${raw%.*}") # 2026-10-20_12-16-26, config/'s FilenameFormatting
	name=$(slug "${4:-}")
	base="${stamp:0:4}${stamp:5:2}${stamp:8:2}-${name:-${stamp:11}}"
	if [ "$m" = video ]; then ext=mp4 && map=(-map 0); fi
	dst="$dir/$base.$ext"
	while [ -e "$dst" ]; do dst="$dir/$base-$i.$ext" && i=$((i + 1)); done
	mkdir -p "$dir"
	ffmpeg -nostdin -loglevel error -y -i "$raw" "${map[@]}" -c copy "$dst" ||
		{ echo "saving failed, the recording is still at $raw" >&2 && return 1; }
	rm "$raw"
	echo "$dst"
}

setup() {
	[ -d /Applications/OBS.app ] || brew install --cask obs
	if pgrep -qf "$obs_pattern"; then
		! pgrep -q obs-ffmpeg-mux || { echo "OBS is recording, stop it first" >&2 && return 1; }
		# OBS rewrites its config on quit, so it has to be closed while this writes.
		osascript -e 'tell application "OBS" to quit' >/dev/null 2>&1 || true
		for _ in $(seq 20); do pgrep -qf "$obs_pattern" || break; sleep 1; done
		! pgrep -qf "$obs_pattern" ||
			{ echo "OBS did not quit, a window in it may be open: close it, quit OBS, run this again" >&2 && return 1; }
	fi
	mkdir -p "$out/.obs"
	# config/ mirrors OBS's own folder. Copied, not stowed: OBS replaces a
	# symlink with a file when it saves. user.ini only on a fresh install.
	(cd "$here/config" && find . -type f) | while read -r f; do
		[ "$f" = ./user.ini ] && [ -e "$conf/user.ini" ] && continue
		mkdir -p "$(dirname "$conf/$f")"
		sed "s|@RECORDINGS@|$out|g" "$here/config/$f" >"$conf/$f"
	done
	ws enable
	echo "OBS is set up. On its first start macOS asks for Microphone and Screen Recording: allow both."
}

# The answer comes from OBS itself, so a setting changed by hand in its window wins.
use() { # use <Get…List request> <current… field> <Set… request> <name field> <value>
	[ "$(ws "$1" '{}' "$2")" = "$5" ] || { ws "$3" "{\"$4\": \"$5\"}" >/dev/null && sleep 1; }
}

start() {
	local m=${1:-} display
	if [ -z "$m" ]; then read -rp "Record audio or video? [audio] " m || true; fi
	m=$(mode "$m")
	[ -e "$conf/basic/profiles/MeetVideo/basic.ini" ] || setup
	pgrep -qf "$obs_pattern" || open -g -a OBS
	for _ in $(seq 30); do ws GetVersion >/dev/null 2>&1 && break; sleep 1; done
	ws GetVersion >/dev/null || { echo "OBS does not answer: is a dialog open in its window?" >&2 && return 1; }

	use GetSceneCollectionList currentSceneCollectionName SetCurrentSceneCollection sceneCollectionName "MeetCall"
	if [ "$m" = video ]; then
		use GetProfileList currentProfileName SetCurrentProfile profileName "MeetVideo"
		# The display's id differs per Mac, so config/ cannot carry it. Read from
		# macOS: asking OBS for its display list crashes it (32.2).
		display=$(osascript -l JavaScript "$here/display.js")
		ws SetInputSettings "{\"inputName\": \"Display\", \"inputSettings\": {\"display_uuid\": \"$display\"}}" >/dev/null
		ws SetCurrentProgramScene '{"sceneName": "Screen"}' >/dev/null
	else
		use GetProfileList currentProfileName SetCurrentProfile profileName "MeetAudio"
		ws SetCurrentProgramScene '{"sceneName": "Audio"}' >/dev/null
	fi
	ws StartRecord >/dev/null
	echo "Recording $m. Stop it with: make record-stop"
}

stop() {
	local p raw name=${1:-}
	if [ -z "$name" ]; then read -rp "Name the recording (Enter = the time): " name || true; fi
	p=$(ws GetProfileList '{}' currentProfileName)
	raw=$(ws StopRecord '{}' outputPath)
	# StopRecord answers before the muxer has closed the file.
	for _ in $(seq 30); do pgrep -q obs-ffmpeg-mux || break; sleep 1; done
	if [ "$p" = "MeetVideo" ]; then save video "$raw" "$out" "$name"; else save audio "$raw" "$out" "$name"; fi
}

case "${1:-}" in
setup) setup ;;
start) start "${2:-}" ;;
stop) stop "${2:-}" ;;
mode) mode "${2:-}" ;;
slug) slug "$2" ;;
save) save "$2" "$3" "$4" "${5:-}" ;;
*) sed -n 's/^# usage: /usage: /p; s/^#        /       /p' "$0" >&2 && exit 2 ;;
esac
