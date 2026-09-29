#!/usr/bin/env bash
# Self-contained: builds a throwaway $HOME/projects with a repo, a submodule and
# a worktree, feeds the hook the JSON Claude Code would, and checks which edits
# it refuses.
set -euo pipefail
hook="$(cd "$(dirname "$0")" && pwd)/checkout-guard.sh"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export TMPDIR="$t" HOME="$t"
# Global signing or a global hooks path must not decide whether this passes.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
g() { git -c user.name=t -c user.email=t@t -c protocol.file.allow=always "$@"; }

p="$t/projects"
g init -q -b main "$p/sub" && touch "$p/sub/f" && g -C "$p/sub" add . && g -C "$p/sub" commit -qm init
g init -q -b main "$p/repo"
printf 'ignored/\n' >"$p/repo/.gitignore"
g -C "$p/repo" submodule -q add "$p/sub" sub
g -C "$p/repo" add . && g -C "$p/repo" commit -qm init
g -C "$p/repo" worktree add -q "$p/repo/.claude/worktrees/w" -b w
g -C "$p/repo/.claude/worktrees/w" submodule -q update --init
mkdir "$t/home" && ln -s ../projects/repo/README.md "$t/home/link.md" && touch "$p/repo/README.md"
g init -q -b main "$p/empty"
cp -R "$p/repo" "$t/scratch"

fail=0
check() { # expected path [session] [key]
  out=$(jq -n --arg p "$2" --arg s "${3-s1}" --arg k "${4:-file_path}" \
    '{session_id: $s, cwd: "/", tool_input: {($k): $p}}' | bash "$hook")
  got=allow
  if [ -n "$out" ]; then
    jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$out" >/dev/null && got=deny || got="bad output"
  fi
  if [ "$got" = "$1" ]; then echo "ok   $1 ${2#"$t"/}"; else echo "FAIL want $1, got $got: $2"; fail=1; fi
}

check deny  "$p/repo/README.md"
check deny  "$p/repo/new/deep/file with space.txt"
check deny  "$p/repo/nb.ipynb" s1 notebook_path
check deny  "$t/home/link.md"                         # a stowed dotfile is a symlink into the checkout
check deny  "$p/repo/sub/f"                           # a submodule of the main checkout
check allow "$p/repo/.claude/worktrees/w/README.md"
check allow "$p/repo/.claude/worktrees/w/sub/f"       # a submodule of a worktree
check allow "$p/repo/ignored/x.txt"
check allow "$p/repo/.git/config"
check allow "$p/empty/README.md"                      # no commits, nothing to branch a worktree from
check allow "$t/scratch/README.md"                    # a repo outside ~/projects
check allow "$t/elsewhere.txt"
GIT_WORK_TREE="$t/scratch" check deny "$p/repo/README.md"  # git env inherited from a git hook
GIT_DIR="$p/repo/.git" check allow "$t/elsewhere.txt"
CDPATH=.:/tmp check deny "$p/repo/README.md"
touch "$t/claude-checkout-ok-"
check deny  "$p/repo/README.md" ""                    # no session id, no way through
touch "$t/claude-checkout-ok-s1"
check allow "$p/repo/README.md"

exit $fail
