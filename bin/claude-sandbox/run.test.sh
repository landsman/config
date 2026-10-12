#!/usr/bin/env bash
# Self-check for ./run.sh: the example scenario passes, and a wrong expectation
# fails it. Needs Docker, and an image that is already built, because building
# one downloads Claude Code and `make bin-test` touches nothing on the machine.
# `make claude-sandbox-test` sets CLAUDE_SANDBOX_BUILD=1 to allow the build.
set -eu

dir="$(cd "$(dirname "$0")" && pwd)"

if ! docker info >/dev/null 2>&1; then
	echo "skip: no Docker daemon"; exit 0
fi
version=$(sed -n 's/^ARG CLAUDE_VERSION=//p' "$dir/Dockerfile")
if [ -z "${CLAUDE_SANDBOX_BUILD:-}" ] && ! docker image inspect "claude-sandbox:$version" >/dev/null 2>&1; then
	echo "skip: no claude-sandbox:$version image (make claude-sandbox-test builds it)"; exit 0
fi

out=$("$dir/run.sh" "$dir/scenarios/late-rule" p) || { echo "$out"; echo "FAIL the example scenario"; exit 1; }
echo "$out"
echo "ok   the example scenario: early rule present, late rule absent"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -a "$dir/scenarios/late-rule/." "$tmp/"
echo "present LATE-RULE-MARKER" > "$tmp/expect"
if "$dir/run.sh" "$tmp" p >/dev/null; then
	echo "FAIL a wrong expectation passed"; exit 1
fi
echo "ok   a wrong expectation fails"
