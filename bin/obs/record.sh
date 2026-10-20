#!/usr/bin/env bash
# Records a call (Google Meet or any other) with OBS without touching its audio:
# what the Mac plays is tapped through ScreenCaptureKit and the mic is read as
# it is, so the call app keeps its own devices and nobody hears a difference.
# The whole Mac rather than one app, so it works whatever the call runs in;
# mute notifications during a call, they get recorded too.
#
# OBS is driven over its built-in websocket (obsws.py). Tracks: 1 = both mixed,
# 2 = the call, 3 = my mic; a player plays the first. Audio mode still records
# a black 640x360 frame at 50 kbps, OBS cannot record without video, and drops
# it when saving.
#
# usage: record.sh setup                  install OBS and set it up (quits OBS first)
#        record.sh start [audio|video]    asks which when not given, Enter = audio
#        record.sh stop                   stop, save to ~/Recordings, print the path
#        record.sh mode <answer>          the answer to "audio or video?", as audio|video
#        record.sh save <mode> <raw> <dir> convert OBS's raw file into <dir>, print the path
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

save() {
	local m=$1 raw=$2 dir=$3 dst
	local -a map=(-map 0:a)
	dst="$dir/$(basename "${raw%.*}")"
	if [ "$m" = video ]; then dst+=.mp4 && map=(-map 0); else dst+=.m4a; fi
	mkdir -p "$dir"
	ffmpeg -nostdin -loglevel error -y -i "$raw" "${map[@]}" -c copy "$dst" ||
		{ echo "saving failed, the recording is still at $raw" >&2 && return 1; }
	rm "$raw"
	echo "$dst"
}

# profile <dir> <name> <width> <height> <fps> <encoder> <encoder settings json>
profile() {
	mkdir -p "$conf/basic/profiles/$1"
	cat >"$conf/basic/profiles/$1/basic.ini" <<EOF
[General]
Name=$2

[Output]
Mode=Advanced

[AdvOut]
RecType=Standard
RecFilePath=$out/.obs
RecFormat2=mkv
RecEncoder=$6
RecTracks=7
Track1Bitrate=192
Track2Bitrate=192
Track3Bitrate=192
Track1Name=Mix
Track2Name=Call
Track3Name=Me

[Video]
BaseCX=$3
BaseCY=$4
OutputCX=$3
OutputCY=$4
FPSType=0
FPSCommon=$5

[Audio]
SampleRate=48000
ChannelSetup=Stereo
EOF
	echo "$7" >"$conf/basic/profiles/$1/recordEncoder.json"
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
	mkdir -p "$conf/basic/scenes" "$out/.obs"

	profile MeetAudio "Meet audio" 640 360 10 obs_x264 '{"rate_control": "CBR", "bitrate": 50}'
	profile MeetVideo "Meet video" 1920 1080 30 \
		com.apple.videotoolbox.videoencoder.ave.avc '{"rate_control": "ABR", "bitrate": 4000}'

	# mixers is a bitmask of the tracks a source feeds: 3 = 1+2, 5 = 1+3.
	# bounds_type 2 scales the screen to fit 1920x1080, whatever the display is.
	cat >"$conf/basic/scenes/MeetCall.json" <<EOF
{
  "name": "Meet call",
  "current_scene": "Audio",
  "current_program_scene": "Audio",
  "scene_order": [{"name": "Audio"}, {"name": "Screen"}],
  "sources": [
    {"id": "scene", "versioned_id": "scene", "name": "Audio",
     "settings": {"items": [], "id_counter": 0}},
    {"id": "scene", "versioned_id": "scene", "name": "Screen",
     "settings": {"id_counter": 1, "items": [
       {"name": "Display", "id": 1, "visible": true, "align": 5,
        "pos": {"x": 0.0, "y": 0.0}, "scale": {"x": 1.0, "y": 1.0},
        "bounds_type": 2, "bounds_align": 0, "bounds": {"x": 1920.0, "y": 1080.0}}]}},
    {"id": "screen_capture", "versioned_id": "screen_capture", "name": "Display",
     "settings": {"type": 0, "show_cursor": true}}
  ],
  "AuxAudioDevice1": {"id": "sck_audio_capture", "versioned_id": "sck_audio_capture",
    "name": "Call (Mac audio)", "mixers": 3, "volume": 1.0,
    "settings": {"type": 0}},
  "AuxAudioDevice2": {"id": "coreaudio_input_capture", "versioned_id": "coreaudio_input_capture",
    "name": "Mic", "mixers": 5, "volume": 1.0,
    "settings": {"device_id": "default"}}
}
EOF
	ws enable

	# Skip the first-run wizard, on a fresh install only: rewriting these drops
	# what OBS stored there since, and it shows the permissions dialog again.
	# OBS 31+ reads user.ini, older versions global.ini.
	for f in user.ini global.ini; do
		[ -e "$conf/$f" ] && continue
		printf '[General]\nFirstRun=true\n\n[Basic]\nProfile=Meet audio\nProfileDir=MeetAudio\nSceneCollection=Meet call\nSceneCollectionFile=MeetCall\n' >"$conf/$f"
	done
	echo "OBS is set up. On its first start macOS asks for Microphone and Screen Recording: allow both."
}

# The answer comes from OBS itself, so a setting changed by hand in its window wins.
use() { # use <Get…List request> <current… field> <Set… request> <name field> <value>
	[ "$(ws "$1" '{}' "$2")" = "$5" ] || { ws "$3" "{\"$4\": \"$5\"}" >/dev/null && sleep 1; }
}

start() {
	local m=${1:-}
	if [ -z "$m" ]; then read -rp "Record audio or video? [audio] " m || true; fi
	m=$(mode "$m")
	[ -e "$conf/basic/profiles/MeetVideo/basic.ini" ] || setup
	pgrep -qf "$obs_pattern" || open -g -a OBS
	for _ in $(seq 30); do ws GetVersion >/dev/null 2>&1 && break; sleep 1; done
	ws GetVersion >/dev/null || { echo "OBS does not answer: is a dialog open in its window?" >&2 && return 1; }

	use GetSceneCollectionList currentSceneCollectionName SetCurrentSceneCollection sceneCollectionName "Meet call"
	if [ "$m" = video ]; then
		use GetProfileList currentProfileName SetCurrentProfile profileName "Meet video"
		ws SetCurrentProgramScene '{"sceneName": "Screen"}' >/dev/null
	else
		use GetProfileList currentProfileName SetCurrentProfile profileName "Meet audio"
		ws SetCurrentProgramScene '{"sceneName": "Audio"}' >/dev/null
	fi
	ws StartRecord >/dev/null
	echo "Recording $m. Stop it with: make record-stop"
}

stop() {
	local p raw
	p=$(ws GetProfileList '{}' currentProfileName)
	raw=$(ws StopRecord '{}' outputPath)
	# StopRecord answers before the muxer has closed the file.
	for _ in $(seq 30); do pgrep -q obs-ffmpeg-mux || break; sleep 1; done
	if [ "$p" = "Meet video" ]; then save video "$raw" "$out"; else save audio "$raw" "$out"; fi
}

case "${1:-}" in
setup) setup ;;
start) start "${2:-}" ;;
stop) stop ;;
mode) mode "${2:-}" ;;
save) save "$2" "$3" "$4" ;;
*) sed -n 's/^# usage: /usage: /p; s/^#        /       /p' "$0" >&2 && exit 2 ;;
esac
