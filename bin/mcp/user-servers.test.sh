#!/usr/bin/env bash
# What user-servers.sh gets wrong silently: re-registering a server that is
# already right (which signs it out), or keeping one whose URL changed.
set -eu

script="$(cd "$(dirname "$0")" && pwd)/user-servers.sh"
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fails=0

check() {  # check <behaviour> <expected> <actual>
	if [ "$2" = "$3" ]; then echo "ok   $1"; else
		echo "FAIL $1"; echo "  expected: $2"; echo "  actual:   $3"; fails=$((fails + 1))
	fi
}

echo '{"mcpServers":{"cloudflare":{"type":"http","url":"https://mcp.cloudflare.com/mcp"}}}' > "$t/same.json"
echo '{"mcpServers":{"cloudflare":{"type":"http","url":"https://old.example/mcp"}}}' > "$t/old.json"
echo '{"mcpServers":{"pencil":{"type":"stdio","command":"x"}}}' > "$t/other.json"

check "a server registered as written is kept" "keep cloudflare" "$("$script" plan "$t/same.json")"
check "a server whose URL changed is replaced" "replace cloudflare" "$("$script" plan "$t/old.json")"
check "a missing server is added" "add cloudflare" "$("$script" plan "$t/other.json")"
check "no ~/.claude.json at all means add" "add cloudflare" "$("$script" plan "$t/missing.json")"

# install against a stub claude: a kept server runs no claude command at all.
mkdir -p "$t/bin" "$t/home"
printf '#!/bin/sh\necho "$*" >> "%s/calls"\n' "$t" > "$t/bin/claude"
chmod +x "$t/bin/claude"
cp "$t/same.json" "$t/home/.claude.json"
CLAUDE_JSON="$t/home/.claude.json" PATH="$t/bin:$PATH" "$script" install > /dev/null
check "install leaves a kept server alone" "" "$(cat "$t/calls" 2>/dev/null)"
cp "$t/old.json" "$t/home/.claude.json"
CLAUDE_JSON="$t/home/.claude.json" PATH="$t/bin:$PATH" "$script" install > /dev/null
check "install removes before re-adding a changed server" \
	"mcp remove cloudflare -s user|mcp add-json -s user cloudflare {\"type\":\"http\",\"url\":\"https://mcp.cloudflare.com/mcp\"}" \
	"$(paste -sd'|' "$t/calls")"

echo
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
