#!/usr/bin/env bash
# Claude Code PreToolUse hook: refuse an anonymous fetch of a host behind a login.
#
# A link to my own forge is private, so WebFetch and a bare curl get a login
# page; an agent handed a PR link once burned five calls on that before trying
# the MCP server that was signed in all along. A skill claims a host with
# `private-hosts:` in its frontmatter and says which tool reads it; this turns
# the first wrong call into a refusal that names that skill. Adding a host is
# writing its skill — nothing here changes.
#
# Let through: git itself (the remote carries credentials), and a curl that
# sends a token — it is no longer anonymous.
set -euo pipefail

input=$(cat)
tool=$(jq -r '.tool_name // ""' <<<"$input")
case $tool in
WebFetch) target=$(jq -r '.tool_input.url // ""' <<<"$input") ;;
Bash) target=$(jq -r '.tool_input.command // ""' <<<"$input") ;;
*) exit 0 ;;
esac

if [ "$tool" = Bash ]; then
	grep -Eq '(^|[^[:alnum:]_-])(curl|wget|xh)([^[:alnum:]_-]|$)' <<<"$target" || exit 0
	grep -Eiq 'authorization|token' <<<"$target" && exit 0
fi

# Same skill folders skill-reminder.py reads.
for f in "$HOME"/.claude/skills/*/SKILL.md ${CLAUDE_PROJECT_DIR:+"$CLAUDE_PROJECT_DIR"/.claude/skills/*/SKILL.md}; do
	[ -f "$f" ] || continue
	meta=$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1' "$f")
	name=$(sed -n 's/^name:[[:space:]]*//p' <<<"$meta")
	for host in $(sed -n 's/^private-hosts:[[:space:]]*//p' <<<"$meta" | tr ',' ' '); do
		h=${host//./\\.}
		if [ "$tool" = WebFetch ]; then
			grep -Eq "^https?://$h([:/]|$)" <<<"$target" || continue
		else
			grep -Eq "(^|[^[:alnum:].-])$h([^[:alnum:].-]|$)" <<<"$target" || continue
		fi
		reason="$host is behind a login; an anonymous fetch gets a login page. Load the ${name:-$(basename "$(dirname "$f")")} skill - it names the signed-in tool that reads this URL. If that tool is missing from this session, say so instead of scraping."
		jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse",
		  permissionDecision: "deny", permissionDecisionReason: $r}}'
		exit 0
	done
done
