#!/usr/bin/env bash
# Self-check for ./forge-guard.sh: tool calls piped in the way Claude Code sends them.
set -euo pipefail
hook="$(cd "$(dirname "$0")" && pwd)/forge-guard.sh"
fail=0
check() { # expected tool key value
	out=$(jq -n --arg t "$2" --arg k "$3" --arg v "$4" '{tool_name: $t, tool_input: {($k): $v}}' | bash "$hook")
	got=allow
	[ -n "$out" ] && { jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$out" >/dev/null && got=deny || got="bad output"; }
	if [ "$got" = "$1" ]; then echo "ok   $1 $2 $4"; else echo "FAIL want $1, got $got: $2 $4"; fail=1; fi
}
u=https://git.insuit.cz/owner/repo/pulls/7

check deny  WebFetch url "$u"
check deny  Bash command "curl -s $u"
check deny  Bash command "curl -s https://git.insuit.cz/api/v1/repos/o/r/pulls/7 | jq ."
check deny  Bash command "wget -qO- $u"
check allow Bash command "curl -H \"Authorization: token \$FORGEJO_ACCESS_TOKEN\" $u"
check allow Bash command "git clone https://git.insuit.cz/owner/repo.git"
check allow Bash command "git fetch origin && curl -s https://example.com"
check allow Bash command "grep -rn git.insuit.cz shared/"
check allow WebFetch url "https://example.com/git.insuit.cz-is-not-here"
check allow Read file_path "$u"
exit "$fail"
