#!/usr/bin/env bash
# Self-check for ./private-host-guard.sh: a throwaway $HOME with skills claiming
# hosts, tool calls piped in the way Claude Code sends them. Last, the repo's own
# skills: a claimed host must also be a trigger keyword, or a pasted link is
# refused without the skill ever having been suggested.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
hook="$here/private-host-guard.sh"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export HOME="$t"; unset CLAUDE_PROJECT_DIR
s="$t/.claude/skills"
mkdir -p "$s/forge" "$s/wiki" "$s/crlf" "$s/plain" "$s/locked"
printf -- '---\nname: forgejo\nprivate-hosts: git.example.cz, "ci.example.cz"\n---\nbody\n' > "$s/forge/SKILL.md"
printf -- '---\nname: wiki\nprivate-hosts: [*.example.net]\n---\n' > "$s/wiki/SKILL.md"
printf -- '---\r\nname: crlf\r\nprivate-hosts: crlf.example.org\r\n---\r\n' > "$s/crlf/SKILL.md"
printf -- '---\nname: plain\n---\nprivate-hosts: not-in-frontmatter.cz\n' > "$s/plain/SKILL.md"
printf -- '---\nname: locked\n---\n' > "$s/locked/SKILL.md" && chmod 000 "$s/locked/SKILL.md"

fail=0
check() { # expected tool value
	local key=command out got rc=0
	[ "$2" = WebFetch ] && key=url
	out=$(jq -n --arg t "$2" --arg k "$key" --arg v "$3" '{tool_name: $t, tool_input: {($k): $v}}' | bash "$hook") || rc=$?
	got=allow
	[ -n "$out" ] && { jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$out" >/dev/null && got=deny || got="bad output"; }
	[ "$rc" -eq 0 ] || got="exit $rc"
	if [ "$got" = "$1" ]; then echo "ok   $1 $2 $3"; else echo "FAIL want $1, got $got: $2 $3"; fail=1; fi
}
u=https://git.example.cz/owner/repo/pulls/7

check deny  WebFetch "$u"
check deny  WebFetch "HTTPS://GIT.EXAMPLE.CZ/x"
check deny  WebFetch "https://user@git.example.cz/x"
check deny  WebFetch "https://git.example.cz?x=1"
check deny  WebFetch "https://git.example.cz./x"
check deny  WebFetch "https://ci.example.cz/run/1"                 # a quoted second host
check deny  WebFetch "https://acme.example.net/wiki/x"             # a wildcard host
check deny  WebFetch "https://crlf.example.org/x"                  # a skill saved with CRLF
check allow WebFetch "https://example.net/x"                       # *. needs a subdomain
check allow WebFetch "https://example.com/git.example.cz-is-not-here"
check allow WebFetch "https://agit.example.cz/x"
check allow WebFetch "https://not-in-frontmatter.cz/x"
check deny  Bash "curl -s $u"
check deny  Bash "curl -s https://git.example.cz:3000/api/v1/repos/o/r/pulls/7 | jq ."
check deny  Bash "wget -qO- $u"
check deny  Bash "curl http://GIT.EXAMPLE.CZ/x"
check deny  Bash "curl https://git.example.cz/user/settings/applications/token"  # a path is not auth
check deny  Bash "U=$u; curl \"\$U\""
check allow Bash "curl -H \"Authorization: token \$FORGEJO_ACCESS_TOKEN\" $u"
check allow Bash "curl -H \"X-Key: \$FJ_PAT\" $u"
check allow Bash "curl -u user:pass $u"
check allow Bash "curl --netrc $u"
check allow Bash "curl -b cookies.txt $u"
check allow Bash "git clone $u.git"
check allow Bash "ssh -T git@git.example.cz"
check allow Bash "git fetch origin && curl -s https://example.com"
check allow Bash "rg 'curl .*git.example.cz' docs"
check allow Bash "sed -i 's|url = .*|url = git.example.cz # curl wrapper|' f"
check allow Bash "glab api projects/1"
check allow Bash "curl -s https://agit.example.cz/x"
check allow Read "$u"
if jq -n --arg u "$u" '{tool_name: "WebFetch", tool_input: {url: $u}}' | bash "$hook" | grep -q 'forgejo skill'; then
	echo "ok   the refusal names the skill"
else
	echo "FAIL the refusal names the skill"; fail=1
fi
if echo '{not json' | bash "$hook" >/dev/null 2>&1; then echo "ok   bad input is let through"; else echo "FAIL bad input blocks"; fail=1; fi

for f in "$here"/../../shared/.agents/skills/*/SKILL.md; do
	hosts=$(sed -n 's/^private-hosts:[[:space:]]*//p' "$f" | tr ',' ' ')
	keys=$(sed -n 's/^trigger-keywords:[[:space:]]*//p' "$f")
	for h in $hosts; do
		case ", $keys," in *", $h,"*) echo "ok   $h is a trigger keyword of $(basename "$(dirname "$f")")" ;;
		*) echo "FAIL $h is in private-hosts but not trigger-keywords: $f"; fail=1 ;; esac
	done
done
exit "$fail"
