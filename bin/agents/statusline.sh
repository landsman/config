#!/usr/bin/env bash
# Claude Code status line: the ponytail badge, then what this session alone
# has used — its tokens (subagents included) and its part of the 5-hour and
# 7-day plan limits. Reads the status line JSON on stdin.
#
#   statusline.sh                              print the line
#   statusline.sh tokens <jsonl> <cache>       print one transcript's token total
#   statusline.sh share <state> <pct> <reset>  print the session's part of a window
#
# The input carries no running token total, so the total is summed from the
# transcripts. Each one's sum is cached with the byte
# offset it covers: an unchanged transcript is not read at all, and a grown
# one only from that offset.
set -euo pipefail

# tokens <jsonl> <cache>: input, cache writes and output of every API response
# in the transcript. Cache reads are left out: each call rereads the whole
# context, so they grow with its length and would swamp what was spent. A
# response is written once per content block, so a repeated message id counts
# once.
tokens() {
	local jsonl=$1 cache=$2 seen=0 total=0 last=- size add used
	[ -f "$cache" ] && read -r seen total last < "$cache"
	# The cache is arithmetic input, and bash evaluates an expression there.
	[[ $seen =~ ^[0-9]+$ && $total =~ ^[0-9]+$ ]] || { seen=0 total=0 last=-; }
	size=$(stat -c %s "$jsonl" 2>/dev/null || stat -f %z "$jsonl")
	# Smaller than cached: the file was replaced, start over.
	[ "$size" -lt "$seen" ] && { seen=0 total=0 last=-; }
	if [ "$size" -gt "$seen" ]; then
		# Only lines that end in a newline are counted and consumed, so a line
		# still being written is left for the next refresh rather than lost.
		read -r add used last < <(tail -c +"$((seen + 1))" "$jsonl" | head -c "$((size - seen))" |
			jq -Rsr --arg last "$last" '
				split("\n")[:-1] as $whole
				| [$whole[] | fromjson? | select(.type == "assistant" and .message.usage) | .message] as $m
				| ($m | map(select(.id != $last)) | unique_by(.id)
					| map(.usage | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.output_tokens // 0)) | add // 0)
				as $add
				| "\($add) \($whole | map(utf8bytelength + 1) | add // 0) \($m[-1].id // $last)"')
		total=$((total + add))
		printf '%s %s %s\n' "$((seen + used))" "$total" "$last" > "$cache.$$" && mv "$cache.$$" "$cache"
	fi
	echo "$total"
}

# share <state> <pct> <resets_at>: this session's part of a plan window. The
# input's percentage is the whole account's, so the session's part is how far
# it moved since the session's first response. A window that resets mid-session
# (it fell, or resets_at jumped) banks what was used before and starts from 0.
share() {
	local state=$1 pct=$2 reset=$3 base='' r0='' acc='' last='' num='^[0-9]+([.][0-9]+)?$'
	[ -f "$state" ] && read -r base r0 acc last < "$state"
	# The state is arithmetic input; anything else than a number starts over.
	[[ $base =~ $num && $r0 =~ $num && $acc =~ $num && $last =~ $num ]] ||
		{ base=$pct r0=$reset acc=0 last=$pct; }
	awk -v base="$base" -v r0="$r0" -v acc="$acc" -v last="$last" -v pct="$pct" -v reset="$reset" \
		-v state="$state.$$" 'BEGIN {
		if (pct < last || reset - r0 > 600 || r0 - reset > 600) { acc += last - base; base = 0; r0 = reset }
		printf "%s %s %s %s\n", base, r0, acc, pct > state
		printf "%.1f\n", acc + pct - base }'
	mv "$state.$$" "$state"
}

human() { awk -v n="$1" 'BEGIN {
	if (n >= 1e9) printf "%.1fG", n / 1e9; else if (n >= 1e6) printf "%.1fM", n / 1e6
	else if (n >= 1e3) printf "%.0fk", n / 1e3; else printf "%d", n }'; }

line() {
	local input session transcript dir sum=0 f out=() w pct reset badge sep
	input=$(cat)
	# The newest installed ponytail, which owns the badge; none prints nothing.
	local hooks=("$HOME"/.claude/plugins/cache/ponytail/ponytail/*/hooks/ponytail-statusline.sh)
	badge=
	[ -f "${hooks[${#hooks[@]} - 1]}" ] && badge=$(bash "${hooks[${#hooks[@]} - 1]}")
	printf '%s' "$badge"

	session=$(jq -r '.session_id // empty' <<< "$input")
	transcript=$(jq -r '.transcript_path // empty' <<< "$input")
	[ -n "$session" ] || return 0
	# With TMPDIR unset that is the shared /tmp, where another user could
	# plant the folder: only one that is ours, private and no link is used.
	dir="${TMPDIR:-/tmp}/claude-statusline-$(id -u)"
	mkdir -m 700 "$dir" 2>/dev/null || true
	[ -O "$dir" ] && [ ! -L "$dir" ] && chmod 700 "$dir" || return 0
	dir="$dir/$session"
	mkdir -p "$dir"
	if [ -f "$transcript" ]; then
		for f in "$transcript" "${transcript%.jsonl}"/subagents/*.jsonl; do
			[ -f "$f" ] && sum=$((sum + $(tokens "$f" "$dir/$(basename "$f").cache")))
		done
		out+=("$(human "$sum") tok")
	fi
	for w in five_hour:5h seven_day:7d; do
		read -r reset pct < <(jq -r --arg w "${w%:*}" \
			'.rate_limits[$w] // {} | "\(.resets_at // 0) \(.used_percentage // "")"' <<< "$input")
		[ -n "$pct" ] && out+=("${w#*:} $(share "$dir/${w%:*}.limit" "$pct" "$reset")%")
	done

	sep=${badge:+ }
	for f in ${out[@]+"${out[@]}"}; do printf '%s%s' "$sep" "$f"; sep=' · '; done
}

case ${1:-} in
	tokens) tokens "$2" "$3" ;;
	share) share "$2" "$3" "$4" ;;
	"") line ;;
	*) echo "usage: statusline.sh [tokens <jsonl> <cache> | share <state> <pct> <reset>]" >&2; exit 2 ;;
esac
