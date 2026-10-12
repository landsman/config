#!/usr/bin/env bash
# Creates a rule two seconds in, the way the repo's own SessionStart hook links
# rules into ~/.claude/rules. Does the session that runs it get the rule?
stamp "SessionStart begin"
sleep 2
echo "Marker: LATE-RULE-MARKER" > "$HOME/.claude/rules/late.md"
stamp "SessionStart end (late.md created)"
echo "SESSION-START-STDOUT-MARKER"
