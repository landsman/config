#!/usr/bin/env bash
# Tells me when a newer major of Claude Code is out than the one the sandbox pins.
#
#   check-version.sh newer-major <pinned> <latest>   exit 0 when latest's major is higher
#   check-version.sh report                          compare the Dockerfile with the release
#                                                    source, open or update one GitHub issue
#
# Dependabot cannot see `ARG CLAUDE_VERSION`, so this is the watch. Minor and
# patch bumps are left alone on purpose: the example scenario is the check for
# those, and a weekly issue per release would be noise. Needs gh and a token
# with issues: write for `report`.
#
# TODO: replace this script and its workflow with a Renovate custom regex
# manager on `ARG CLAUDE_VERSION` (and the two checksums), once Renovate runs
# here - one config block instead of a script, a test and a pipeline.
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
title="claude-sandbox: a newer Claude Code major is out"

newer_major() { [ "${2%%.*}" -gt "${1%%.*}" ]; }

case "${1:-}" in
newer-major)
	newer_major "${2:?pinned}" "${3:?latest}"
	;;
report)
	pinned=$(sed -n 's/^ARG CLAUDE_VERSION=//p' "$dir/Dockerfile")
	latest=$(curl -fsSL https://downloads.claude.ai/claude-code-releases/latest)
	if ! newer_major "$pinned" "$latest"; then
		echo "pinned $pinned, latest $latest: same major"; exit 0
	fi
	body="The sandbox pins Claude Code $pinned and $latest is out. To move: change \`CLAUDE_VERSION\` and both \`CLAUDE_SHA256_*\` in bin/claude-sandbox/Dockerfile, then run \`make claude-sandbox-test\`."
	# One issue, edited rather than duplicated, so a week of silence is not a week of mail.
	n=$(gh issue list --state open --search "\"$title\" in:title" --json number --jq '.[0].number // empty')
	if [ -n "$n" ]; then gh issue edit "$n" --body "$body"; else gh issue create --title "$title" --body "$body"; fi
	;;
*)
	sed -n '2,6p' "$0" >&2; exit 2
	;;
esac
