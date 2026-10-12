#!/usr/bin/env bash
# Inside the container: lay the scenario out, run Claude Code against the fake
# API, leave the evidence in /out. Not meant to be run by hand; see run.sh.
#
#   entry.sh p|tty
set -eu

mode=${1:?usage: entry.sh p|tty}
export SBX_OUT=/out
home=/sbx/home
work=/sbx/work
port=47613
key=sk-ant-api03-invalidsandboxkey-0123456789abcdefghij

mkdir -p "$home/.claude" "$work" /sbx/tmp
[ -d /scenario/home ] && cp -a /scenario/home/. "$home/"
[ -d /scenario/work ] && cp -a /scenario/work/. "$work/"
prompt=$(cat /scenario/prompt)

# Interactive Claude Code asks about onboarding, the API key and folder trust;
# answering in advance is what makes the run unattended.
cat > "$home/.claude/.claude.json" <<JSON
{ "hasCompletedOnboarding": true, "theme": "dark", "numStartups": 5,
  "customApiKeyResponses": { "approved": ["${key: -20}"], "rejected": [] },
  "projects": { "$work": { "hasTrustDialogAccepted": true, "hasCompletedProjectOnboarding": true } } }
JSON
cp "$home/.claude/.claude.json" "$home/.claude.json"

perl /opt/sbx/server.pl "$port" /out &
sleep 1
stamp "claude ($mode) launched"

# env -i: nothing from the container's own environment leaks in either.
run=(env -i PATH="$PATH" HOME="$home" CLAUDE_CONFIG_DIR="$home/.claude" TMPDIR=/sbx/tmp
	SBX_OUT=/out ANTHROPIC_API_KEY="$key" ANTHROPIC_BASE_URL="http://127.0.0.1:$port"
	CLAUDE_CODE_MAX_RETRIES=0 DISABLE_AUTOUPDATER=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_TELEMETRY=1)
cd "$work"
if [ "$mode" = p ]; then
	"${run[@]}" TERM=dumb timeout 90 claude -p "$prompt" --max-turns 1 > /out/claude.out 2>&1 || echo "claude exited $?" >> /out/claude.out
else
	# The prompt is typed once the UI is up, then Ctrl-C twice to leave.
	{ sleep 8; printf '%s' "$prompt"; sleep 1; printf '\r'; sleep 8; printf '\003'; sleep 1; printf '\003'; } |
		"${run[@]}" TERM=xterm-256color timeout 40 script -q -c claude /out/claude.out >/dev/null 2>&1 || true
fi
stamp "claude ($mode) ended"
