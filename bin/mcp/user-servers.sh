#!/usr/bin/env bash
# Registers the servers in user-servers.json at Claude Code's user scope, so
# /mcp lists them under User MCPs rather than among the plugin servers.
#
#   user-servers.sh install                 register what is missing or changed
#   user-servers.sh plan <claude.json>      print `<action> <name>` per server: keep, add or replace
#
# Idempotent: a server already registered as written is kept, so a second run
# does not drop its OAuth sign-in.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
servers="$here/user-servers.json"

plan() {  # plan <claude.json>
	local have='{}'
	[ -f "$1" ] && have=$(jq -c '.mcpServers // {}' "$1")
	jq -r --argjson have "$have" '
		.mcpServers | to_entries[]
		| if $have[.key] == null then "add \(.key)"
		  elif ($have[.key] | del(.env)) == .value then "keep \(.key)"
		  else "replace \(.key)" end
	' "$servers"
}

install() {
	plan "${CLAUDE_JSON:-$HOME/.claude.json}" | while read -r action name; do
		[ "$action" = keep ] && { echo "keep    $name"; continue; }
		[ "$action" = replace ] && claude mcp remove "$name" -s user >/dev/null
		claude mcp add-json -s user "$name" "$(jq -c --arg n "$name" '.mcpServers[$n]' "$servers")" >/dev/null
		echo "$action $name"
	done
}

case "${1:-}" in
	install) install ;;
	plan) plan "${2:?usage: user-servers.sh plan <claude.json>}" ;;
	*) echo "usage: user-servers.sh install | plan <claude.json>" >&2; exit 2 ;;
esac
