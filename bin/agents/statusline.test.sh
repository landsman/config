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

msg() { # msg <id> <tokens>: one response, <tokens> each of input, cache write and
	# output, and a million cache reads that must not count
	printf '{"type":"assistant","message":{"id":"%s","usage":{"input_tokens":%d,"cache_creation_input_tokens":%d,"cache_read_input_tokens":1000000,"output_tokens":%d}}}\n' "$1" "$2" "$2" "$2"
}
expect() { # expect <behaviour> <want> <got>
	if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "  want: $2"; echo "  got:  $3"; fails=$((fails + 1)); fi
}
total() { "$script" tokens "$log" "$cache"; }

{ msg a 1; msg a 1; echo '{"type":"user"}'; msg b 10; } > "$log"
expect "a response written per content block counts once, and cache reads not at all" 33 "$(total)"

{ msg b 10; msg c 100; } >> "$log"
expect "a refresh adds only the appended lines, across the cached boundary" 333 "$(total)"

msg d 1000 | tr -d '\n' >> "$log"
expect "a line still being written is not counted yet" 333 "$(total)"
echo >> "$log"
expect "and is counted once it is complete" 3333 "$(total)"

msg z 2 > "$log"
expect "a replaced, shorter transcript is summed from the start" 6 "$(total)"

echo "0 a[\$(touch $tmp/pwned)] -" > "$cache"
expect "a planted cache is discarded, not evaluated" "6:no" "$(total):$([ -e "$tmp/pwned" ] && echo yes || echo no)"

mkdir "$tmp/elsewhere"
ln -s "$tmp/elsewhere" "$tmp/claude-statusline-$(id -u)"
out=$(jq -nc --arg t "$log" '{session_id:"sess",transcript_path:$t}' | "$script")
expect "a cache folder that is a link is not used" "" "$out"
rm "$tmp/claude-statusline-$(id -u)"

mkdir -p "$tmp/t/sess/subagents"
msg m 1 > "$tmp/t/sess.jsonl"
msg s 5 > "$tmp/t/sess/subagents/agent-1.jsonl"
line() { # line <5h pct> <5h resets_at>: the status line for session "sess"
	jq -nc --arg t "$tmp/t/sess.jsonl" --argjson p "$1" --argjson r "$2" '{session_id:"sess",transcript_path:$t,
		rate_limits:{five_hour:{used_percentage:$p,resets_at:$r},seven_day:{used_percentage:41.2,resets_at:9000000}}}' | "$script"
}
expect "the session starts at none of the plan, whatever the account used before" "18 tok · 5h 0.0% · 7d 0.0%" "$(line 23.5 18000)"
expect "the line adds the subagents, and only this session's part of a window" "18 tok · 5h 1.5% · 7d 0.0%" "$(line 25 18000)"

out=$(jq -nc --arg t "$tmp/t/sess.jsonl" '{session_id:"sess",transcript_path:$t,
	rate_limits:{five_hour:{used_percentage:25,resets_at:18000}}}' | "$script")
expect "a window missing from the input is left out, not shown as 0" "18 tok · 5h 1.5%" "$out"

state="$tmp/w.limit"
share() { "$script" share "$state" "$1" "$2"; }
share 40 18000 > /dev/null
share 42.5 18000 > /dev/null
expect "a window that resets keeps what was used before it, and counts the new one from 0" 3.5 "$(share 1 36000)"
expect "a resets_at that only jitters is not a reset" 4.5 "$(share 2 36030)"
echo "0 0 a[\$(touch $tmp/pwned2)] 0" > "$state"
expect "a planted window state is discarded, not evaluated" "0.0:no" "$(share 7 1):$([ -e "$tmp/pwned2" ] && echo yes || echo no)"

out=$(echo '{}' | "$script") && rc=0 || rc=$?
expect "an input without session or limits prints nothing and exits 0" "0:" "$rc:$out"

exit $((fails > 0))
