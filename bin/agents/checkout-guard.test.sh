#!/usr/bin/env bash
# Self-contained: builds a throwaway repo with a submodule and a worktree, feeds
# the hook the JSON Claude Code would, and checks which edits it refuses.
set -euo pipefail
hook="$(cd "$(dirname "$0")" && pwd)/checkout-guard.sh"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export TMPDIR="$t"
g() { git -c user.name=t -c user.email=t@t -c protocol.file.allow=always "$@"; }

g init -q -b main "$t/sub" && touch "$t/sub/f" && g -C "$t/sub" add . && g -C "$t/sub" commit -qm init
g init -q -b main "$t/repo"
printf 'ignored/\n' >"$t/repo/.gitignore"
g -C "$t/repo" submodule -q add "$t/sub" sub
g -C "$t/repo" add . && g -C "$t/repo" commit -qm init
g -C "$t/repo" worktree add -q "$t/repo/.claude/worktrees/w" -b w
g -C "$t/repo/.claude/worktrees/w" submodule -q update --init
mkdir "$t/home" && ln -s ../repo/README.md "$t/home/link.md" && touch "$t/repo/README.md"

fail=0
check() { # expected path [session] [key]
  out=$(jq -n --arg p "$2" --arg s "${3-s1}" --arg k "${4:-file_path}" \
    '{session_id: $s, cwd: "/", tool_input: {($k): $p}}' | bash "$hook")
  got=allow
  if [ -n "$out" ]; then
    jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$out" >/dev/null && got=deny || got="bad output"
  fi
  if [ "$got" = "$1" ]; then echo "ok   $1 $2"; else echo "FAIL want $1, got $got: $2"; fail=1; fi
}

check deny  "$t/repo/README.md"
check deny  "$t/repo/new/deep/file with space.txt"
check deny  "$t/repo/nb.ipynb" s1 notebook_path
check deny  "$t/home/link.md"                         # a stowed dotfile is a symlink into the checkout
check deny  "$t/repo/sub/f"                           # a submodule of the main checkout
check allow "$t/repo/.claude/worktrees/w/README.md"
check allow "$t/repo/.claude/worktrees/w/sub/f"       # a submodule of a worktree
check allow "$t/repo/ignored/x.txt"
check allow "$t/repo/.git/config"
check allow "$t/elsewhere.txt"
touch "$t/claude-checkout-ok-"
check deny  "$t/repo/README.md" ""                    # no session id, no way through
touch "$t/claude-checkout-ok-s1"
check allow "$t/repo/README.md"

exit $fail
