#!/usr/bin/env bash
# The MCP server list, in the two shapes a client can read, and the check that
# the two copies still agree.
#
# Two files rather than one, because the formats are not the same: Claude Code
# reads a plugin's .mcp.json, where a stdio server is `command` plus `args`
# under `mcpServers`, while opencode reads its own config, where it is a single
# argv array under `mcp` and the schema allows nothing else (each entry is
# `additionalProperties: false`, and a `type` it does not know is an error). No
# symlink serves both, so the list is written twice.
#
# What is checkable is that the two copies name the same servers and run the
# same command — the half that rots. A server added to one file and not the
# other is not an error anywhere: it is a client that quietly does not have it.
# That is how forgejo came to exist for Claude Code and not for opencode.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
claude="$root/shared/.agents/skills/mcp-servers/.mcp.json"
opencode="$root/shared/.config/opencode/opencode.json"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

# Servers opencode has and Claude Code does not. Declared here rather than
# inferred from the diff, because a name only one file may carry is a decision
# and the decision has to be visible in review. pencil is the one: Pen.app is
# macOS-only, so it cannot sit in a file every machine reads.
opencode_only="pencil"

# One line per server — `name<TAB>what it runs` — from either format, so the
# two are comparable. The formats differ in how a command is spelled, not in
# what it does: Claude splits it across `command` and `args`, opencode keeps it
# in one array. Reading it as a single argv line is what makes a guard that
# drifted between the copies show up as a diff rather than as a subtlety.
sigs() {  # sigs <file> <claude|opencode> <out>
	python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
servers = d["mcpServers"] if sys.argv[2] == "claude" else d["mcp"]
for name, s in sorted(servers.items()):
    if s["type"] in ("http", "remote"):
        what = "url " + s["url"]
    else:
        # Claude: `command` is a string and `args` carries the rest.
        # opencode: `command` is already the whole argv array, and there
        # are no `args`.
        argv = s["command"] if isinstance(s["command"], list) \
            else [s["command"]] + s.get("args", [])
        what = "argv " + " ".join(argv)
    print(name + "\t" + what)
' "$1" "$2" > "$3"
}

for pair in "$claude:claude" "$opencode:opencode"; do
	f=${pair%:*}
	[ -f "$f" ] || { echo "FAIL $f is missing"; exit 1; }
	sigs "$f" "${pair##*:}" "$tmp/${pair##*:}" \
		|| { echo "FAIL $f is not readable as a server list"; exit 1; }
done

# Drop the declared exceptions by name rather than by line pattern, so a server
# whose name is a prefix of another is not exempted along with it.
awk -F'\t' -v ex="$opencode_only" '
	BEGIN { n = split(ex, a, " "); for (i = 1; i <= n; i++) e[a[i]] = 1 }
	!($1 in e)
' "$tmp/opencode" > "$tmp/opencode-minus-exceptions"
cut -f1 "$tmp/opencode" > "$tmp/opencode-names"

# A diff that passes because the filter removed everything is a check that ran
# and proved nothing, so the list it compared is asserted to be non-empty first.
check() {  # check <name> <expected> <actual>
	if [ "$2" = "$3" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1"; echo "  expected: $2"; echo "  actual:   $3"; fails=$((fails + 1))
	fi
}
check "the opencode list is not empty once the exceptions are removed" 1 \
	"$([ -s "$tmp/opencode-minus-exceptions" ] && echo 1 || echo 0)"

if diff -u "$tmp/claude" "$tmp/opencode-minus-exceptions" > "$tmp/diff"; then
	echo "ok   both lists name the same servers and run the same command"
else
	echo "FAIL the two lists disagree"; sed 's/^/  /' "$tmp/diff"; fails=$((fails + 1))
fi

# Every exception has to still be a server opencode has. One that outlived its
# server goes on excusing a name that has since been added to that list on
# purpose — a filter that is never re-read stops filtering.
for n in $opencode_only; do
	if grep -qx "$n" "$tmp/opencode-names"; then
		echo "ok   $n is still opencode-only, as declared"
	else
		echo "FAIL $n is declared opencode-only but is not in the opencode config"
		fails=$((fails + 1))
	fi
done

echo
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
