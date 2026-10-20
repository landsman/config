#!/usr/bin/env bash
# What record.sh would get wrong silently: Enter not meaning audio, a video
# saved as audio-only (or the reverse), and the raw recording deleted when
# saving it failed — that last one loses the call.
set -uo pipefail

script="$(cd "$(dirname "$0")" && pwd)/record.sh"
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
mkdir "$t/bin"
cat >"$t/bin/ffmpeg" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$T/ffmpeg.log"
[ -z "${FFMPEG_FAIL:-}" ] || exit 1
touch "${@: -1}"
EOF
chmod +x "$t/bin/ffmpeg"
export PATH="$t/bin:$PATH" T="$t"
rc=0
check() { # check <name> <expected> <actual>
	if [ "$2" = "$3" ]; then echo "ok   $1"; else
		echo "FAIL $1"; echo "  expected: $2"; echo "  actual:   $3"; rc=1
	fi
}
exists() { [ -e "$1" ] && echo yes || echo no; }

check "Enter means audio" audio "$("$script" mode "")"
check "v means video" video "$("$script" mode v)"
check "anything else is refused" 1 "$("$script" mode x 2>/dev/null; echo $?)"

touch "$t/call.mkv"
check "audio is saved as .m4a and the path printed" "$t/out/call.m4a" "$("$script" save audio "$t/call.mkv" "$t/out")"
check "audio keeps every audio track and no video" "-i $t/call.mkv -map 0:a -c copy $t/out/call.m4a" "$(tail -1 "$t/ffmpeg.log" | sed 's/.*-y //')"
check "the raw file goes once it is saved" no "$(exists "$t/call.mkv")"

touch "$t/screen.mkv"
check "video is saved as .mp4 and the path printed" "$t/out/screen.mp4" "$("$script" save video "$t/screen.mkv" "$t/out")"
check "video keeps everything" "-i $t/screen.mkv -map 0 -c copy $t/out/screen.mp4" "$(tail -1 "$t/ffmpeg.log" | sed 's/.*-y //')"

touch "$t/broken.mkv"
check "a failed save fails" 1 "$(FFMPEG_FAIL=1 "$script" save audio "$t/broken.mkv" "$t/out" 2>/dev/null; echo $?)"
check "a failed save keeps the raw recording" yes "$(exists "$t/broken.mkv")"

exit $rc
