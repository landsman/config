#!/usr/bin/env bash
# Run a scenario in Claude Code inside a container and say what reached the model.
#
#   run.sh <scenario-dir> [p|tty|both]      (default p; tty is the interactive UI)
#
# A scenario is a directory with:
#   home/     copied over the container's $HOME - .claude/settings.json, rules,
#             skills, hook scripts, CLAUDE.md
#   work/     the project directory the session starts in (optional)
#   prompt    what to type
#   expect    optional, one line each: "present <text>" or "absent <text>" -
#             the text is looked for in the requests, and the exit status is
#             1 when any line is wrong
#
# The container has no network (loopback only), mounts nothing from the host's
# $HOME, and talks to a fake API that records each request and answers 401. The
# raw requests stay in the output directory, printed at the end.
set -eu

dir="$(cd "$(dirname "$0")" && pwd)"
scenario=$(cd "${1:?usage: run.sh <scenario-dir> [p|tty|both]}" && pwd)
modes=${2:-p}
[ "$modes" = both ] && modes="p tty"
[ -f "$scenario/prompt" ] || { echo "$scenario/prompt is missing" >&2; exit 2; }

# The version is whatever the Dockerfile pins; the image tag follows it, so a
# bump builds a new image instead of silently reusing the old one.
version=$(sed -n 's/^ARG CLAUDE_VERSION=//p' "$dir/Dockerfile")
image="claude-sandbox:$version"
docker build -q -t "$image" "$dir" >/dev/null   # layer cache makes this instant once built

fails=0
for mode in $modes; do
	out=$(mktemp -d "${TMPDIR:-/tmp}/claude-sandbox.XXXXXX")
	# No --network: the default bridge would reach out. "none" leaves loopback.
	docker run --rm --network none --cap-drop ALL --security-opt no-new-privileges \
		--user "$(id -u):$(id -g)" -v "$scenario:/scenario:ro" -v "$out:/out" \
		"$image" "$mode" >/dev/null

	echo "== $(basename "$scenario"), claude $version, mode $mode"
	echo "-- timeline (seconds since launch)"
	sort -n "$out/timeline.log" | awk 'NR == 1 { t0 = $1 } { printf "%7.2f ", $1 - t0; $1 = ""; print substr($0, 2) }'

	reqs=$(find "$out" -name 'req-*.json' | sort -V)
	echo "-- requests: $(echo "$reqs" | grep -c .)"
	if [ -f "$scenario/expect" ] && [ -n "$reqs" ]; then
		echo "-- expect (count of occurrences per request)"
		while read -r want text; do
			[ -n "$want" ] || continue
			counts=$(for r in $reqs; do grep -aoF -- "$text" "$r" | wc -l | tr -d ' '; done | tr '\n' ' ')
			total=$(echo "$counts" | tr ' ' '+' | sed 's/+$//' | bc)
			if { [ "$want" = present ] && [ "$total" -gt 0 ]; } || { [ "$want" = absent ] && [ "$total" -eq 0 ]; }; then
				verdict=ok
			else verdict=FAIL; fails=$((fails + 1)); fi
			printf '%-4s %-8s %-40s [%s]\n' "$verdict" "$want" "$text" "${counts% }"
		done < "$scenario/expect"
	elif [ -f "$scenario/expect" ]; then
		echo "FAIL no request reached the fake API; see $out/claude.out"; fails=$((fails + 1))
	fi
	echo "-- raw: $out (req-N.json, timeline.log, claude.out)"
done
[ "$fails" -eq 0 ]
