#!/usr/bin/env bash
# Self-check for ./quote-to-fence.py: MessageDisplay batches piped in the way
# Claude Code sends them, one message split over several calls, the calls run
# concurrently as 2.1.296 does. Each case joins what would be shown.
set -eu

hook="$(cd "$(dirname "$0")" && pwd)/quote-to-fence.py"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export TMPDIR="$tmp"
fails=0

show() { # show <message id> <batch>... ; prints the joined display, batches started together
	local id=$1 n=$(($# - 1)) i=0
	shift
	for delta in "$@"; do
		jq -n --arg m "$id" --arg d "$delta" --argjson i "$i" --argjson f "$([ "$i" -eq $((n - 1)) ] && echo true || echo false)" \
			'{message_id: $m, index: $i, final: $f, delta: $d}' |
			python3 "$hook" > "$tmp/out.$i" &
		printf '%s' "$delta" > "$tmp/in.$i"
		i=$((i + 1))
	done
	wait
	for ((i = 0; i < n; i++)); do
		if [ -s "$tmp/out.$i" ]; then jq -j '.hookSpecificOutput.displayContent' "$tmp/out.$i"; else cat "$tmp/in.$i"; fi
	done
	rm -f "$tmp"/out.* "$tmp"/in.*
}

check() { # check <name> <expected display> <message id> <batch>...
	local name=$1 want=$2 got
	shift 2
	got=$(show "$@"; echo .) # the dot keeps trailing newlines, which $(...) strips
	got=${got%.}
	if [ "$got" = "$want" ]; then echo "ok   $name"; else
		echo "FAIL $name"; printf '  want: %q\n  got:  %q\n' "$want" "$got"; fails=$((fails + 1))
	fi
}

check "a quote becomes a fenced block" $'Hi\n```markdown\nDobrý den,\n[odkaz](https://x.cz)\n```\nend' \
	m1 $'Hi\n> Dobrý den,\n> [odkaz](https://x.cz)\nend'
check "a quote run over three batches stays one block" $'```markdown\na\nb\nc\n```\nend' \
	m2 $'> a\n' $'> b\n' $'> c\nend'
check "a run still open at the end is closed" $'x\n```markdown\na\n```\n' \
	m3 $'x\n' '> a'
check "a > inside the message's own fence is content" $'```bash\n> inside\n```\n```markdown\nq\n```\n' \
	m4 $'```bash\n' $'> inside\n' $'```\n> q\n'
check "a four-backtick fence holds a three-backtick one" $'````md\n```\n> nested\n```\n````\n' \
	m5 $'````md\n```\n' $'> nested\n```\n````\n'
check "a quote holding backticks gets a longer fence" $'````markdown\nrun ```make```\n````\n' \
	m6 "> run \`\`\`make\`\`\`"
check "a nested list quote loses its marker" $'- item\n```markdown\nnote\n```\n' \
	m7 $'- item\n  > note\n'
check "plain text is left alone" $'a > b\n    > indented code\n' \
	m8 $'a > b\n    > indented code\n'

# A batch that never reports (crashed, killed) must not stall the rest of the message for long.
start=$(date +%s)
out=$(jq -n '{message_id: "m9", index: 3, final: false, delta: "> late\n"}' | python3 "$hook")
took=$(($(date +%s) - start))
next=$(jq -n '{message_id: "m9", index: 4, final: true, delta: "> later\n"}' | python3 "$hook")
if [ -z "$out" ] && [ -z "$next" ] && [ "$took" -le 7 ]; then echo "ok   a lost batch passes the rest through, once"; else
	echo "FAIL a lost batch passes the rest through, once (took ${took}s, out=$out next=$next)"; fails=$((fails + 1))
fi
if [ -z "$(ls "$tmp/claude-quote-to-fence" 2>/dev/null)" ]; then echo "ok   no state is left behind"; else
	echo "FAIL no state is left behind"; ls "$tmp/claude-quote-to-fence"; fails=$((fails + 1))
fi

[ "$fails" -eq 0 ]
