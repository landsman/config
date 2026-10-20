#!/usr/bin/env bash
# What record.sh would get wrong silently: Enter not meaning audio, a video
# saved as audio-only (or the reverse), a recording overwriting an earlier one
# of the same name, and the raw recording deleted when saving it failed — those
# last two lose a call.
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

raw="$t/2026-10-20_12-16-26.mkv"
touch "$raw"
check "audio is saved as .m4a, named date-name, and the path printed" "$t/out/20261020-porada-s-sarkou.m4a" "$("$script" save audio "$raw" "$t/out" "Porada s Šárkou!")"
check "audio keeps every audio track and no video" "-i $raw -map 0:a -c copy $t/out/20261020-porada-s-sarkou.m4a" "$(tail -1 "$t/ffmpeg.log" | sed 's/.*-y //')"
check "the raw file goes once it is saved" no "$(exists "$raw")"

touch "$raw"
check "a second recording of the same name gets -2, never overwrites" "$t/out/20261020-porada-s-sarkou-2.m4a" "$("$script" save audio "$raw" "$t/out" "porada s sarkou")"

touch "$raw"
check "no name means date and time" "$t/out/20261020-12-16-26.m4a" "$("$script" save audio "$raw" "$t/out" "")"

touch "$raw"
check "video is saved as .mp4 and the path printed" "$t/out/20261020-demo.mp4" "$("$script" save video "$raw" "$t/out" demo)"
check "video keeps everything" "-i $raw -map 0 -c copy $t/out/20261020-demo.mp4" "$(tail -1 "$t/ffmpeg.log" | sed 's/.*-y //')"

touch "$raw"
check "a failed save fails" 1 "$(FFMPEG_FAIL=1 "$script" save audio "$raw" "$t/out" x 2>/dev/null; echo $?)"
check "a failed save keeps the raw recording" yes "$(exists "$raw")"

exit $rc
