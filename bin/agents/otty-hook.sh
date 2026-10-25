#!/usr/bin/env bash
# Claude Code hook: tell Otty whether this agent is working, waiting or idle,
# which it shows on the tab. Otty's own installer writes the same hooks straight
# into ~/.claude/settings.json, which replaces the stowed symlink with a copy;
# this keeps them in the repo. A no-op where Otty is not installed — Linux, or
# a Mac without it. $1 is the state, $2 the agent's pid ($PPID of the hook).
hook=/Applications/Otty.app/Contents/Resources/agent-integration/claude/otty-hook.sh
[ -x "$hook" ] || exit 0
OTTY_CLI=/Applications/Otty.app/Contents/MacOS/otty-cli exec "$hook" "$@"
