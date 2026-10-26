#!/usr/bin/env bash
# Self-check for ./statusline.sh. What it would get wrong silently is the
# token total: a response counted once per content block, an appended line
# counted twice or never, a half-written line dropped, a stale cache kept.
set -eu

script="$(cd "$(dirname "$0")" && pwd)/statusline.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
# The real jq, resolved before HOME moves: a mise shim reads its config from
# HOME, and a throwaway HOME is one it does not trust.
mkdir "$tmp/bin"
ln -s "$(type -ap jq | grep -v /shims/ | head -1)" "$tmp/bin/jq"
export HOME="$tmp" TMPDIR="$tmp" PATH="$tmp/bin:$PATH"
log="$tmp/s.jsonl" cache="$tmp/s.cache"

msg() { # msg <id> <tokens>: one transcript line of a response, all four kinds
	printf '{"type":"assistant","message":{"id":"%s","usage":{"input_tokens":%d,"cache_creation_input_tokens":%d,"cache_read_input_tokens":%d,"output_tokens":%d}}}\n' "$1" "$2" "$2" "$2" "$2"
}
expect() { # expect <behaviour> <want> <got>
	if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "  want: $2"; echo "  got:  $3"; fails=$((fails + 1)); fi
}
total() { "$script" tokens "$log" "$cache"; }

{ msg a 1; msg a 1; echo '{"type":"user"}'; msg b 10; } > "$log"
expect "a response written per content block counts once" 44 "$(total)"

{ msg b 10; msg c 100; } >> "$log"
expect "a refresh adds only the appended lines, across the cached boundary" 444 "$(total)"

msg d 1000 | tr -d '\n' >> "$log"
expect "a line still being written is not counted yet" 444 "$(total)"
echo >> "$log"
expect "and is counted once it is complete" 4444 "$(total)"

msg z 2 > "$log"
expect "a replaced, shorter transcript is summed from the start" 8 "$(total)"

mkdir -p "$tmp/t/sess/subagents"
msg m 1 > "$tmp/t/sess.jsonl"
msg s 5 > "$tmp/t/sess/subagents/agent-1.jsonl"
out=$(jq -nc --arg t "$tmp/t/sess.jsonl" '{session_id:"sess",transcript_path:$t,
	rate_limits:{five_hour:{used_percentage:23.5},seven_day:{used_percentage:41.2}}}' | "$script")
expect "the line adds the subagents and floors the plan percentages" "24 tok · 5h 23% · 7d 41%" "$out"

out=$(echo '{}' | "$script") && rc=0 || rc=$?
expect "an input without session or limits prints nothing and exits 0" "0:" "$rc:$out"

exit $((fails > 0))
