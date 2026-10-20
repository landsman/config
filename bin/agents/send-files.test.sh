#!/usr/bin/env bash
# Self-check for ./send-files.ts: Stop hook input piped in the way Claude Code
# sends it, against small transcripts written here. What it would get wrong
# silently: letting a named screenshot through unsent, holding a turn for a file
# already sent or one that does not exist, or holding the same turn twice.
set -euo pipefail

hook="$(cd "$(dirname "$0")" && pwd)/send-files.ts"
# The binary itself: make runs this under a bash that mise has not put bun on PATH for.
bun=$(mise which bun 2>/dev/null || command -v bun)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
touch "$t/shot.png" "$t/Main.kt"
fails=0

prompt() { jq -cn --arg s "$1" '{type: "user", message: {role: "user", content: $s}}'; }
say() { jq -cn --arg s "$1" '{type: "assistant", message: {role: "assistant", content: [{type: "text", text: $s}]}}'; }
send() { jq -cn --arg f "$1" '{type: "assistant", message: {role: "assistant", content: [{type: "tool_use", name: "SendUserFile", input: {files: [$f]}}]}}'; }
result() { jq -cn '{type: "user", message: {role: "user", content: [{type: "tool_result", content: "ok"}]}}'; }

check() { # check <behaviour> <block|pass> <stop_hook_active> ; transcript lines on stdin
	local name=$1 want=$2 active=$3 got
	cat > "$t/transcript.jsonl"
	got=$(jq -n --arg p "$t/transcript.jsonl" --argjson a "$active" '{transcript_path: $p, stop_hook_active: $a}' |
		"$bun" "$hook" | jq -r '.decision // empty')
	got=${got:-pass}
	if [ "$got" = "$want" ]; then echo "ok   $name"; else
		echo "FAIL $name (want $want, got $got)"; fails=$((fails + 1))
	fi
}

{ prompt "ukaz to"; say "Snímek je v $t/shot.png."; } |
	check "a screenshot named but never sent holds the turn" block false
{ prompt "ukaz to"; send "$t/shot.png"; result; say "Poslal jsem $t/shot.png."; } |
	check "a screenshot sent in the same turn passes" pass false
{ prompt "ukaz to"; send "$t/shot.png"; result; say "hotovo"; prompt "a dal?"; say "Pořád platí $t/shot.png."; } |
	check "a screenshot sent in an earlier turn passes" pass false
{ prompt "ukaz to"; say "Snímek bude v $t/later.png."; } |
	check "a path that does not exist passes" pass false
{ prompt "kde to je"; say "Viz $t/Main.kt:12."; } |
	check "a source file is a reference and passes" pass false
{ prompt "ukaz to"; say "Snímek je v $t/shot.png."; } |
	check "the stop after a block is let through" pass true
{ prompt "ukaz to"; say "Snímek je v $t/shot.png."; prompt "dalsi"; say "hotovo"; } |
	check "a path named in an earlier turn only passes" pass false
{ prompt "ukaz to"; result; say "Snímek: \`$t/shot.png\`"; } |
	check "a path in backticks after a tool result still counts" block false

exit $((fails > 0))
