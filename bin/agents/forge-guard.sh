#!/usr/bin/env bash
# Claude Code PreToolUse hook: refuse an anonymous fetch of git.insuit.cz.
#
# The repos there are private, so WebFetch and a bare curl get a login page,
# and an agent handed a PR link burned five calls on that before trying the
# forgejo MCP server. The forgejo skill maps each URL to its tool; this turns
# the first wrong call into a refusal that names them.
#
# Let through: git itself (the remote carries credentials), and a curl that
# sends a token — it is no longer anonymous.
#
# ponytail: one host. Add a case arm when another private forge comes along.
set -euo pipefail

input=$(cat)
tool=$(jq -r '.tool_name // ""' <<<"$input")
case $tool in
WebFetch) target=$(jq -r '.tool_input.url // ""' <<<"$input") ;;
Bash) target=$(jq -r '.tool_input.command // ""' <<<"$input") ;;
*) exit 0 ;;
esac

if [ "$tool" = WebFetch ]; then
	grep -Eq '^https?://git\.insuit\.cz([:/]|$)' <<<"$target" || exit 0
else
	grep -q 'git\.insuit\.cz' <<<"$target" || exit 0
	grep -Eq '(^|[^[:alnum:]_-])(curl|wget|xh)([^[:alnum:]_-]|$)' <<<"$target" || exit 0
	grep -Eiq 'authorization|token' <<<"$target" && exit 0
fi

reason="git.insuit.cz is a private Forgejo; an anonymous fetch gets a login page. Load the forgejo skill and use the forgejo MCP server: ToolSearch select:mcp__forgejo__get_pull_request_by_index,mcp__forgejo__list_pull_reviews,mcp__forgejo__list_pull_review_comments,mcp__forgejo__list_issue_comments,mcp__forgejo__get_pull_request_diff. No mcp__forgejo__* tools in this session means the server did not start - say so instead of scraping."

jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse",
  permissionDecision: "deny", permissionDecisionReason: $r}}'
