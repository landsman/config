#!/usr/bin/env bash
# Self-contained: builds a throwaway repo with a worktree, feeds the hook the
# JSON Claude Code would, and checks which edits it refuses.
set -euo pipefail
hook="$(cd "$(dirname "$0")" && pwd)/checkout-guard.sh"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export TMPDIR="$t"

git init -q -b main "$t/repo"
printf 'ignored/\n' >"$t/repo/.gitignore"
git -C "$t/repo" add . && git -C "$t/repo" -c user.name=t -c user.email=t@t commit -qm init
git -C "$t/repo" worktree add -q "$t/repo/.claude/worktrees/w" -b w

fail=0
check() { # expected tool path
  out=$(jq -n --arg p "$3" --arg t "$2" '{session_id: "s1", tool_name: $t, tool_input: {file_path: $p}}' | bash "$hook")
  if [ -n "$out" ]; then got=deny; else got=allow; fi
  if [ "$got" = "$1" ]; then echo "ok   $1 $3"; else echo "FAIL want $1, got $got: $3"; fail=1; fi
}

check deny  Edit  "$t/repo/README.md"
check deny  Write "$t/repo/new/deep/file.txt"
check allow Edit  "$t/repo/.claude/worktrees/w/README.md"
check allow Write "$t/repo/ignored/x.txt"
check allow Write "$t/elsewhere.txt"
touch "$t/claude-checkout-ok-s1"
check allow Edit  "$t/repo/README.md"

exit $fail
