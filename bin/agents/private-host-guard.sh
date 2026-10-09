#!/usr/bin/env bash
# Claude Code PreToolUse hook: refuse an anonymous fetch of a host behind a login.
#
# A link to my own forge is private, so WebFetch and a bare curl get a login
# page; an agent handed a PR link once burned five calls on that before trying
# the MCP server that was signed in all along. A skill claims a host with
# `private-hosts:` in its frontmatter (comma separated, `*.` for any subdomain)
# and says which tool reads it; this turns the first wrong call into a refusal
# that names that skill. Adding a host is writing its skill — nothing here changes.
#
# Denied: WebFetch of such a URL, and curl/wget/xh in a Bash command that carries
# one. Let through: a fetch that authenticates (-H, -u, --netrc, a cookie), and
# anything that only mentions the host — git, ssh, grep, a commit message.
#
# ponytail: a nudge, not a boundary. python/node/gh api reach the host unchecked.
set -euo pipefail
command -v jq >/dev/null || exit 0 # fail open, as any non-2 exit would, but quietly

input=$(cat)
tool=$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null) || exit 0
case $tool in
WebFetch) target=$(jq -r '.tool_input.url // "" | strings' <<<"$input") ;;
Bash) target=$(jq -r '.tool_input.command // "" | strings' <<<"$input") ;;
*) exit 0 ;;
esac

if [ "$tool" = Bash ]; then
	grep -Eq '(^|[^[:alnum:]_.-])(curl|wget|xh)([^[:alnum:]_.-]|$)' <<<"$target" || exit 0
	grep -Eq '(^|[[:space:]])(-H|--header|-u|--user|-n|--netrc|--netrc-file|-b|--cookie|--oauth2-bearer)([[:space:]=]|$)' <<<"$target" && exit 0
	url='(https?:)?//'
else
	url='^[[:space:]]*(https?:)?//'
fi
target=$(tr '[:upper:]' '[:lower:]' <<<"$target")

# awk stops at the first file it cannot open, so hand it only the readable ones.
files=()
for f in "$HOME"/.claude/skills/*/SKILL.md ${CLAUDE_PROJECT_DIR:+"$CLAUDE_PROJECT_DIR"/.claude/skills/*/SKILL.md}; do
	[ -r "$f" ] && files+=("$f")
done
[ "${#files[@]}" -gt 0 ] || exit 0

# One awk over every skill: "<skill> <host>" per claimed host. CRLF, quotes and
# [a, b] are tolerated.
claims=$(awk '
	FNR == 1 { fm = 0; name = "" }
	{ sub(/\r$/, "") }
	FNR == 1 && $0 == "---" { fm = 1; next }
	fm && $0 == "---" { fm = 0; nextfile }
	fm && /^name:/ { name = $0; sub(/^name:[[:space:]]*/, "", name) }
	fm && /^private-hosts:/ {
		v = tolower($0); sub(/^private-hosts:/, "", v); gsub(/["'\''\[\]]/, "", v)
		n = split(v, hs, /[,[:space:]]+/)
		for (i = 1; i <= n; i++) if (hs[i] != "") print (name != "" ? name : FILENAME), hs[i]
	}
' "${files[@]}" 2>/dev/null || true)

while read -r skill host; do
	[ -n "${host:-}" ] || continue
	sub=''
	case $host in \*.*) sub='([a-z0-9-]+\.)+' host=${host#\*.} ;; esac # *.example.net: any subdomain
	h=$sub${host//./\\.}
	grep -Eq "$url([^/@[:space:]]*@)?$h\\.?([:/?#\"'[:space:]]|\$)" <<<"$target" || continue
	reason="$host is behind a login; an anonymous fetch gets a login page. Load the $skill skill - it names the signed-in tool that reads this URL. If that tool is missing from this session, say so instead of scraping."
	jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse",
	  permissionDecision: "deny", permissionDecisionReason: $r}}'
	exit 0
done <<<"$claims"
