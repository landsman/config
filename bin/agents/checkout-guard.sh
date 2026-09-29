#!/usr/bin/env bash
# Claude Code PreToolUse hook: refuse a file edit in a repo's main checkout.
#
# The worktrees rule (shared/.agents/rules/worktrees.md) says work that changes
# a repo happens in a git worktree. As text it was loaded and still ignored, so
# this turns it into a refusal the agent cannot miss. A linked worktree has its
# own git dir under the common one; the main checkout's git dir *is* the common
# one — that difference is the whole test.
#
# Allowed through: paths outside any repo, paths git ignores (scratch like
# .claude/), and a session whose user said "do it in my checkout" — the agent
# records that by touching the marker the refusal names.
#
# ponytail: Edit/Write/NotebookEdit only. `sed -i` or `git commit` through Bash
# in the checkout is not caught; add a Bash matcher if agents route around it.
set -euo pipefail

input=$(cat)
session=$(jq -r '.session_id // ""' <<<"$input")
path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")
[ -n "$path" ] || exit 0

marker="${TMPDIR:-/tmp}/claude-checkout-ok-$session"
[ -n "$session" ] && [ -e "$marker" ] && exit 0

# A Write may create the file and its folders; ask git from the nearest one that exists.
dir=$(dirname "$path")
while [ ! -d "$dir" ]; do dir=$(dirname "$dir"); done

git_dir=$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null) || exit 0
common=$(cd "$dir" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
[ "$(cd "$git_dir" && pwd -P)" = "$common" ] || exit 0
git -C "$dir" check-ignore -q "$path" && exit 0

top=$(git -C "$dir" rev-parse --show-toplevel)
reason="$top is the main checkout, and work that changes a repo happens in a git worktree (rules/worktrees.md). Move into one with the EnterWorktree tool, or: git worktree add .claude/worktrees/<name> -b <branch> origin/main. Only if the user explicitly said to work in the checkout for this task: touch $marker"

jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse",
  permissionDecision: "deny", permissionDecisionReason: $r}}'
