#!/usr/bin/env bash
# Self-check for ./private-host-guard.sh: a throwaway $HOME with a skill claiming
# a host, tool calls piped in the way Claude Code sends them.
set -euo pipefail
hook="$(cd "$(dirname "$0")" && pwd)/private-host-guard.sh"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export HOME="$t"; unset CLAUDE_PROJECT_DIR
mkdir -p "$t/.claude/skills/forge" "$t/.claude/skills/plain"
printf -- '---\nname: forgejo\nprivate-hosts: git.example.cz, ci.example.cz\n---\nbody\n' > "$t/.claude/skills/forge/SKILL.md"
printf -- '---\nname: plain\n---\nprivate-hosts: not-in-frontmatter.cz\n' > "$t/.claude/skills/plain/SKILL.md"

fail=0
check() { # expected tool key value
	out=$(jq -n --arg t "$2" --arg k "$3" --arg v "$4" '{tool_name: $t, tool_input: {($k): $v}}' | bash "$hook")
	got=allow
	[ -n "$out" ] && { jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$out" >/dev/null && got=deny || got="bad output"; }
	if [ "$got" = "$1" ]; then echo "ok   $1 $2 $4"; else echo "FAIL want $1, got $got: $2 $4"; fail=1; fi
}
u=https://git.example.cz/owner/repo/pulls/7

check deny  WebFetch url "$u"
check deny  WebFetch url "https://ci.example.cz/run/1"            # a second host on the same skill
check deny  Bash command "curl -s $u"
check deny  Bash command "curl -s https://git.example.cz/api/v1/repos/o/r/pulls/7 | jq ."
check deny  Bash command "wget -qO- $u"
check allow Bash command "curl -H \"Authorization: token \$FORGEJO_ACCESS_TOKEN\" $u"
check allow Bash command "git clone $u.git"
check allow Bash command "git fetch origin && curl -s https://example.com"
check allow Bash command "curl -s https://agit.example.cz/x"     # another host that merely ends the same
check allow WebFetch url "https://example.com/git.example.cz-is-not-here"
check allow WebFetch url "https://not-in-frontmatter.cz/x"       # only frontmatter claims a host
check allow Read file_path "$u"
if jq -n --arg u "$u" '{tool_name: "WebFetch", tool_input: {url: $u}}' | bash "$hook" | grep -q 'forgejo skill'; then
	echo "ok   the refusal names the skill"
else
	echo "FAIL the refusal names the skill"; fail=1
fi
exit "$fail"
