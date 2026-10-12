#!/usr/bin/env bash
# Self-check for ./no-blockquote.py: transcripts written the way Claude Code
# writes them, piped in the way the Stop hook receives them.
set -eu

hook="$(cd "$(dirname "$0")" && pwd)/no-blockquote.py"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

check() { # check <name> <block|pass> <last assistant text> [stop_hook_active]
	jq -cn --arg t "$3" '{type: "assistant", message: {content: [{type: "text", text: $t}]}}' > "$tmp/t.jsonl"
	local out
	out=$(jq -n --arg p "$tmp/t.jsonl" --argjson a "${4:-false}" '{transcript_path: $p, stop_hook_active: $a}' | python3 "$hook")
	if { [ "$2" = pass ] && [ -z "$out" ]; } || { [ "$2" = block ] && [[ "$out" == *'"block"'* ]]; }; then
		echo "ok   $1"
	else
		echo "FAIL $1"; echo "  got: $out"; fails=$((fails + 1))
	fi
}

check "a blockquote is sent back" block $'Návrh:\n\n> Dobrý den,\n> díky.'
check "a quote marker without a space" block $'>Dobrý den'
check "the same text in a code block passes" pass $'Návrh:\n\n```\nDobrý den,\ndíky.\n```'
check "a > inside a code block is content" pass $'```\n> quoted in a paste\n```'
check "a > mid-line is not a quote" pass 'when a > b, stop'
check "an indented code line is not a quote" pass $'text\n\n    > not a quote'
check "a second stop is let through" pass $'> still quoted' true

# A newer Claude Code passes the text directly; it wins over the transcript.
out=$(jq -n '{last_assistant_message: "> quoted"}' | python3 "$hook")
if [[ "$out" == *'"block"'* ]]; then echo "ok   last_assistant_message is read"; else echo "FAIL last_assistant_message is read"; fails=$((fails + 1)); fi

[ "$fails" -eq 0 ]
