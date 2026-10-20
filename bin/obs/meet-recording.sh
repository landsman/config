#!/usr/bin/env bash
# OBS set up to record a call (Google Meet) without touching its audio: what
# the Mac plays is tapped through ScreenCaptureKit and the mic is read as it is,
# so Meet keeps its own devices and nobody hears a difference. The whole Mac,
# not Chrome alone: capturing Chrome by app recorded silence in a test, likely
# because its audio comes from helper processes. Mute notifications in a call.
#
# Tracks: 1 = both mixed, 2 = the call, 3 = my mic. Video is a 640x360 black
# frame at 10 fps and 50 kbps — OBS always records one; at its default 6 Mbps
# an 8-minute call took 365 MB.
#
# usage: meet-recording.sh          writes the "Meet call" profile and scene collection
#        meet-recording.sh export F splits recording F into "F call/them/me.m4a",
#                                   copied as recorded, no re-encoding
set -eu

if [ "${1:-}" = export ]; then
	b="${2%.*}"
	ffmpeg -nostdin -loglevel error -y -i "$2" \
		-map 0:a:0 -c copy "$b call.m4a" -map 0:a:1 -c copy "$b them.m4a" -map 0:a:2 -c copy "$b me.m4a"
	exit
fi

conf="$HOME/Library/Application Support/obs-studio"
name="Meet call"
mkdir -p "$conf/basic/profiles/MeetCall" "$conf/basic/scenes" "$HOME/Movies"

cat >"$conf/basic/profiles/MeetCall/basic.ini" <<EOF
[General]
Name=$name

[Output]
Mode=Advanced

[AdvOut]
RecType=Standard
RecFilePath=$HOME/Movies
RecFormat2=mkv
RecEncoder=obs_x264
RecTracks=7
Track1Bitrate=192
Track2Bitrate=192
Track3Bitrate=192
Track1Name=Mix
Track2Name=Meet
Track3Name=Me

[Video]
BaseCX=640
BaseCY=360
OutputCX=640
OutputCY=360
FPSType=0
FPSCommon=10

[Audio]
SampleRate=48000
ChannelSetup=Stereo
EOF

echo '{"rate_control": "CBR", "bitrate": 50}' >"$conf/basic/profiles/MeetCall/recordEncoder.json"

# mixers is a bitmask of the tracks a source feeds: 3 = 1+2, 5 = 1+3.
cat >"$conf/basic/scenes/MeetCall.json" <<EOF
{
  "name": "$name",
  "current_scene": "Call",
  "current_program_scene": "Call",
  "scene_order": [{"name": "Call"}],
  "sources": [
    {"id": "scene", "versioned_id": "scene", "name": "Call",
     "settings": {"items": [], "id_counter": 0}}
  ],
  "AuxAudioDevice1": {"id": "sck_audio_capture", "versioned_id": "sck_audio_capture",
    "name": "Call (Mac audio)", "mixers": 3, "volume": 1.0,
    "settings": {"type": 0}},
  "AuxAudioDevice2": {"id": "coreaudio_input_capture", "versioned_id": "coreaudio_input_capture",
    "name": "Mic", "mixers": 5, "volume": 1.0,
    "settings": {"device_id": "default"}}
}
EOF

# Make it the active one and skip the first-run wizard. OBS 31+ reads user.ini,
# older versions global.ini. Only on a fresh install: rewriting them drops what
# OBS stored there since, and it shows the permissions dialog again.
for f in user.ini global.ini; do
	[ -e "$conf/$f" ] && continue
	cat >"$conf/$f" <<EOF
[General]
FirstRun=true

[Basic]
Profile=$name
ProfileDir=MeetCall
SceneCollection=$name
SceneCollectionFile=MeetCall
EOF
done

echo "OBS: profile and scene collection \"$name\" written, recordings go to ~/Movies"
