#!/usr/bin/env bash
# Self-check for ./no-blockquote.py: Stop hook input piped in the way Claude
# Code sends it.
set -eu

hook="$(cd "$(dirname "$0")" && pwd)/no-blockquote.py"
fails=0

check() { # check <name> <block|pass> <final reply> [stop_hook_active]
	local out
	out=$(jq -n --arg t "$3" --argjson a "${4:-false}" '{last_assistant_message: $t, stop_hook_active: $a}' | python3 "$hook")
	if { [ "$2" = pass ] && [ -z "$out" ]; } || { [ "$2" = block ] && [[ "$out" == *'"block"'* ]]; }; then
		echo "ok   $1"
	else
		echo "FAIL $1"; echo "  got: $out"; fails=$((fails + 1))
	fi
}

check "a blockquote is sent back" block $'Návrh:\n\n> Dobrý den,\n> díky.'
check "a quote marker without a space" block '>Dobrý den'
check "a quote nested under a list item" block $'- item\n  > note'
check "the same text in a code block passes" pass $'Návrh:\n\n```\nDobrý den,\ndíky.\n```'
check "a > inside a code block is content" pass $'```\n> quoted in a paste\n```'
check "a tilde fence holds a backtick line" pass $'~~~\n```\n> inside\n~~~'
check "a longer fence holds a shorter one" pass $'````markdown\n```bash\n> inside\n```\n````'
check "a quote after a longer fence closes" block $'````md\n```\n````\n> real quote'
check "a closer with an info string does not close" pass $'```\n```bash\n> still inside\n```'
check "a > mid-line is not a quote" pass 'when a > b, stop'
check "an indented code line is not a quote" pass $'text\n\n    > not a quote'
check "an empty reply passes" pass ''
check "a second stop is let through" pass '> still quoted' true

out=$(echo '{}' | python3 "$hook")
if [ -z "$out" ]; then echo "ok   a missing field is let through"; else echo "FAIL a missing field is let through"; fails=$((fails + 1)); fi

[ "$fails" -eq 0 ]
