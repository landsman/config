#!/usr/bin/env bash
# Self-check for ./skill-reminder.py: a throwaway $HOME with two skills, prompts
# piped in the way Claude Code sends them.
set -eu

hook="$(cd "$(dirname "$0")" && pwd)/skill-reminder.py"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
export HOME="$tmp"
unset CLAUDE_PROJECT_DIR

check() { # check <name> <expected substring, or "" for silence> <prompt> [transcript]
	local out
	out=$(jq -n --arg p "$3" --arg t "${4:-}" '{prompt: $p, transcript_path: $t}' | python3 "$hook")
	if { [ -z "$2" ] && [ -z "$out" ]; } || { [ -n "$2" ] && [[ "$out" == *"$2"* ]]; }; then
		echo "ok   $1"
	else
		echo "FAIL $1"; echo "  got: $out"; fails=$((fails + 1))
	fi
}

mkdir -p "$tmp/.claude/skills/git" "$tmp/.claude/skills/pg" "$tmp/.claude/skills/quiet"
printf -- '---\nname: commit-messages\ntrigger-keywords: commit*, pull request\n---\n' > "$tmp/.claude/skills/git/SKILL.md"
printf -- '---\nname: postgres\ntrigger-keywords: postgres, index*\n---\n' > "$tmp/.claude/skills/pg/SKILL.md"
printf -- '---\nname: quiet\ndescription: no keywords\n---\n' > "$tmp/.claude/skills/quiet/SKILL.md"

check "whole word" "load the postgres skill" "why is Postgres slow"
check "a prefix keyword catches an inflected form" "commit-messages" "napiš zprávu ke commitu"
check "a multi-word keyword" "commit-messages" "open a pull request"
check "no partial word without *" "" "postgresql is fine"
check "no match inside a word" "" "the recommit flag"
check "unrelated prompt is silent" "" "hello"

printf '%s\n' '{"message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"postgres"}}]}}' > "$tmp/t.jsonl"
check "a skill loaded this session is not repeated" "" "add an index" "$tmp/t.jsonl"

mkdir -p "$tmp/p/.claude/skills/local"
printf -- '---\nname: local\ntrigger-keywords: deploy\n---\n' > "$tmp/p/.claude/skills/local/SKILL.md"
CLAUDE_PROJECT_DIR="$tmp/p" check "the project's own skills count" "load the local skill" "deploy it"

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
