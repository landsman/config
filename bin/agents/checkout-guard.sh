#!/usr/bin/env bash
# Claude Code PreToolUse hook: refuse a file edit in a repo's main checkout.
#
# The worktrees rule (shared/.agents/rules/worktrees.md) says work that changes
# a repo happens in a git worktree. As text it was loaded and still ignored, so
# this turns it into a refusal the agent cannot miss. A linked worktree has its
# own git dir under the common one; the main checkout's git dir *is* the common
# one — that difference is the whole test.
#
# Only repos under ~/projects/ are guarded — that is where every checkout lives
# (rules/where-repos-live.md), and a scratch repo in /tmp has no checkout to
# protect. Also allowed through: a repo with no commits yet, paths git ignores
# (scratch like .claude/), and a session whose user said "do it in my
# checkout" — the agent records that by touching the marker the refusal names.
#
# ponytail: Edit/Write/NotebookEdit only. `sed -i` or `git commit` through Bash
# in the checkout is not caught; add a Bash matcher if agents route around it.
set -euo pipefail
# Inherited from a git hook that runs Claude Code, these would answer for the
# wrong repo. CDPATH makes `cd` print, which would corrupt $(cd … && pwd).
unset CDPATH
# shellcheck disable=SC2046 # git's own list of variable names, split on purpose
unset $(git rev-parse --local-env-vars)

input=$(cat)
session=$(jq -r '.session_id // ""' <<<"$input")
path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")
[ -n "$path" ] || exit 0
case $path in /*) ;; *) path="$(jq -r '.cwd // "."' <<<"$input")/$path" ;; esac

tmp=${TMPDIR:-/tmp}
marker="${tmp%/}/claude-checkout-ok-$session"
[ -n "$session" ] && [ -e "$marker" ] && exit 0

# Resolve the file itself: every stowed dotfile is a symlink from $HOME into
# the config repo's checkout, and its dirname alone is in no repo at all.
[ -e "$path" ] && path=$(realpath "$path")

# A Write may create the file and its folders; ask git from the nearest one that exists.
dir=$(dirname "$path")
while [ ! -d "$dir" ]; do dir=$(dirname "$dir"); done
dir=$(cd -P "$dir" && pwd)

root=$(cd -P "$HOME/projects" 2>/dev/null && pwd) || exit 0
case $dir/ in "$root"/*) ;; *) exit 0 ;; esac

# Outside a repo, inside .git/, or in a bare repo: nothing to guard.
[ "$(git -C "$dir" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] || exit 0
git -C "$dir" rev-parse -q --verify HEAD >/dev/null || exit 0
git -C "$dir" check-ignore -q "$path" && exit 0

# A submodule's git dir equals its common dir even inside a linked worktree,
# so the checkout-or-worktree question goes to the outermost superproject.
top=$(git -C "$dir" rev-parse --show-toplevel)
while super=$(git -C "$top" rev-parse --show-superproject-working-tree) && [ -n "$super" ]; do top=$super; done

git_dir=$(git -C "$top" rev-parse --absolute-git-dir)
common=$(cd "$top" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
[ "$(cd "$git_dir" && pwd -P)" = "$common" ] || exit 0

base=$(git -C "$top" symbolic-ref -q --short refs/remotes/origin/HEAD) || base="<default branch>"
reason="$top is the main checkout, and work that changes a repo happens in a git worktree (rules/worktrees.md). Move into one with the EnterWorktree tool, or: git worktree add .claude/worktrees/<name> -b <branch> $base. Only if the user explicitly said to work in the checkout for this task: touch $marker"

jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse",
  permissionDecision: "deny", permissionDecisionReason: $r}}'
