#!/usr/bin/env bash
# Self-contained: starts sleeps that are named like a wrangler dev server in
# throwaway directories, and checks which of them the script takes. It is never
# run without a directory here, so a real dev server on this machine survives.
set -euo pipefail
script="$(cd "$(dirname "$0")" && pwd)/kill-dev-servers.sh"
t=$(mktemp -d)
fakes=()
cleanup() { [ ${#fakes[@]} -eq 0 ] || kill -9 "${fakes[@]}" 2>/dev/null || true; rm -rf "$t"; }
trap cleanup EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
g() { git -c user.name=t -c user.email=t@t "$@"; }

g init -q -b main "$t/repo" && touch "$t/repo/f" && g -C "$t/repo" add . && g -C "$t/repo" commit -qm init
w="$t/repo/.claude/worktrees/w"
g -C "$t/repo" worktree add -q "$w" -b w
g -C "$t/repo" worktree add -q "$w-other" -b other
mkdir "$w/site"

# fake <dir> [deaf] — leaves the pid in $pid. Not $(fake …): the sleep would
# hold the substitution's pipe open. A deaf one ignores SIGTERM, as wrangler does.
fake() {
	(cd "$1" && { [ -z "${2-}" ] || trap '' TERM; } && exec -a 'wrangler pages dev' sleep 300) &
	pid=$!
	disown "$pid" # or bash announces every death on stderr
	fakes+=("$pid")
}
# A killed child stays a zombie until this shell reaps it, and kill -0 still
# finds a zombie.
alive() { ps -o stat= -p "$1" 2>/dev/null | grep -qv '^Z'; }

fail=0
check() { # expected pid label
	got=dead
	alive "$2" && got=alive
	if [ "$got" = "$1" ]; then echo "ok   $1 $3"; else echo "FAIL want $1, got $got: $3"; fail=1; fi
}
hook() { jq -n "$@" | bash "$script" --hook >/dev/null; }

fake "$w/site" deaf; in_w=$pid
fake "$w-other";     sibling=$pid
fake "$t/repo";      checkout=$pid
sleep 1 # until each has exec'd into its new name

bash "$script" "$w" >/dev/null
check dead  "$in_w"     "a server below the dir, one that ignores SIGTERM"
check alive "$sibling"  "a worktree whose name only starts the same"
check alive "$checkout" "the main checkout the worktree lives in"

fake "$w/site"; in_w=$pid
sleep 1
hook --arg d "$w" '{reason: "clear", cwd: $d}'
check alive "$in_w"     "hook: a /clear is not the end of the work"
hook --arg d "$t/repo" '{reason: "other", cwd: $d}'
check alive "$checkout" "hook: a session in the main checkout"
check alive "$in_w"     "hook: and that session leaves the worktrees under it alone"
hook --arg d "$w/site" '{reason: "other", cwd: $d}'
check dead  "$in_w"     "hook: a session that ends in a subfolder of the worktree"
check alive "$sibling"  "hook: and the worktree next to it is another session's"

exit $fail
