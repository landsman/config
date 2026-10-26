#!/usr/bin/env bash
# Claude Code status line: the ponytail badge, the tokens this session has
# burned (subagents included), and how much of the 5-hour and 7-day plan
# limits is used. Reads the status line JSON on stdin.
#
#   statusline.sh                       print the line
#   statusline.sh tokens <jsonl> <cache>  print one transcript's token total
#
# The input carries no running token total, only the plan percentages, so the
# total is summed from the transcripts. Each one's sum is cached with the line
# count it covers, and a refresh parses only the lines appended since.
set -euo pipefail

# tokens <jsonl> <cache>: input, cache writes, cache reads and output of every
# API response in the transcript. A response is written once per content
# block, so a repeated message id counts once.
tokens() {
	local jsonl=$1 cache=$2 seen=0 total=0 last=- lines add
	[ -f "$cache" ] && read -r seen total last < "$cache"
	lines=$(wc -l < "$jsonl" | tr -d ' ')
	# Fewer lines than cached: the file was replaced, start over.
	[ "$lines" -lt "$seen" ] && { seen=0 total=0 last=-; }
	if [ "$lines" -gt "$seen" ]; then
		# head -n stops at the last newline, so a line still being written
		# is left for the next refresh rather than lost.
		read -r add last < <(tail -n +"$((seen + 1))" "$jsonl" | head -n "$((lines - seen))" |
			jq -Rnr --arg last "$last" '
				[inputs | fromjson? | select(.type == "assistant" and .message.usage) | .message] as $m
				| ($m | map(select(.id != $last)) | unique_by(.id)
					| map(.usage | (.input_tokens // 0) + (.cache_creation_input_tokens // 0)
						+ (.cache_read_input_tokens // 0) + (.output_tokens // 0)) | add // 0)
				as $add
				| "\($add) \($m[-1].id // $last)"')
		total=$((total + add))
		printf '%s %s %s\n' "$lines" "$total" "$last" > "$cache.$$" && mv "$cache.$$" "$cache"
	fi
	echo "$total"
}

human() { awk -v n="$1" 'BEGIN {
	if (n >= 1e9) printf "%.1fG", n / 1e9; else if (n >= 1e6) printf "%.1fM", n / 1e6
	else if (n >= 1e3) printf "%.0fk", n / 1e3; else printf "%d", n }'; }

line() {
	local input session transcript dir sum=0 f out=() five week badge
	input=$(cat)
	session=$(jq -r '.session_id // empty' <<< "$input")
	transcript=$(jq -r '.transcript_path // empty' <<< "$input")
	if [ -n "$session" ] && [ -f "$transcript" ]; then
		dir="${TMPDIR:-/tmp}/claude-statusline/$session"
		mkdir -p "$dir"
		for f in "$transcript" "${transcript%.jsonl}"/subagents/*.jsonl; do
			[ -f "$f" ] && sum=$((sum + $(tokens "$f" "$dir/$(basename "$f").cache")))
		done
		out+=("$(human "$sum") tok")
	fi
	five=$(jq -r '.rate_limits.five_hour.used_percentage // empty | floor' <<< "$input")
	week=$(jq -r '.rate_limits.seven_day.used_percentage // empty | floor' <<< "$input")
	[ -n "$five" ] && out+=("5h $five%")
	[ -n "$week" ] && out+=("7d $week%")

	# The newest installed ponytail, which owns the badge; none prints nothing.
	local hooks=("$HOME"/.claude/plugins/cache/ponytail/ponytail/*/hooks/ponytail-statusline.sh)
	badge=
	[ -f "${hooks[${#hooks[@]} - 1]}" ] && badge=$(bash "${hooks[${#hooks[@]} - 1]}")
	printf '%s' "$badge"
	local sep=${badge:+ }
	for f in ${out[@]+"${out[@]}"}; do printf '%s%s' "$sep" "$f"; sep=' · '; done
}

case ${1:-} in
	tokens) tokens "$2" "$3" ;;
	"") line ;;
	*) echo "usage: statusline.sh [tokens <jsonl> <cache>]" >&2; exit 2 ;;
esac
