#!/usr/bin/env bash
# Self-contained: starts processes that listen on a port, and some that do not,
# in a throwaway repo with two worktrees, and checks which of them the script
# takes. It is never run with --all here, so a real dev server on this machine
# survives.
set -euo pipefail
script="$(cd "$(dirname "$0")" && pwd)/kill-dev-servers.sh"
t=$(mktemp -d)
started=()
cleanup() { [ ${#started[@]} -eq 0 ] || kill -9 "${started[@]}" 2>/dev/null || true; rm -rf "$t"; }
trap cleanup EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
g() { git -c user.name=t -c user.email=t@t "$@"; }

g init -q -b main "$t/repo" && touch "$t/repo/f" && g -C "$t/repo" add . && g -C "$t/repo" commit -qm init
w="$t/repo/.claude/worktrees/w"
g -C "$t/repo" worktree add -q "$w" -b w
g -C "$t/repo" worktree add -q "$w-other" -b other
mkdir "$w/site"

# start <dir> <command…> — leaves the pid in $pid. Not $(start …): the process
# would hold the substitution's pipe open.
start() {
	(cd "$1" && shift && exec "$@") &
	pid=$!
	disown "$pid" # or bash announces every death on stderr
	started+=("$pid")
}
listen='import socket, time; s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(); time.sleep(300)'
server() { start "$1" python3 -c "$listen"; }
# wrangler sat through SIGTERM; an ignored signal stays ignored across exec.
deaf_server() { start "$1" bash -c 'trap "" TERM; exec python3 -c "$0"' "$listen"; }
bystander() { start "$1" sleep 300; } # the shell or the editor: there, not listening

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

deaf_server "$w/site"; in_w=$pid
bystander "$w/site";   shell=$pid
server "$w-other";     sibling=$pid
server "$t/repo";      checkout=$pid
sleep 1 # until each is listening

bash "$script" --list "$w" | grep -q "^$in_w " || { echo "FAIL --list does not name the server"; fail=1; }
check alive "$in_w"     "--list kills nothing"

bash "$script" "$w" >/dev/null
check dead  "$in_w"     "a server below the dir, one that ignores SIGTERM"
check alive "$shell"    "a process in the same dir that does not listen"
check alive "$sibling"  "a worktree whose name only starts the same"
check alive "$checkout" "the main checkout the worktree lives in"

server "$w/site"; in_w=$pid
sleep 1
hook --arg d "$w" '{reason: "clear", cwd: $d}'
check alive "$in_w"     "hook: a /clear is not the end of the work"
hook --arg d "$t/repo" '{reason: "other", cwd: $d}'
check alive "$checkout" "hook: a session in the main checkout"
check alive "$in_w"     "hook: and that session leaves the worktrees under it alone"
hook --arg d "$t" '{reason: "other", cwd: $d}'
check alive "$in_w"     "hook: a session outside any repo"
hook --arg d "$w/site" '{reason: "other", cwd: $d}'
check dead  "$in_w"     "hook: a session that ends in a subfolder of the worktree"
check alive "$sibling"  "hook: and the worktree next to it is another session's"

bash "$script" 2>/dev/null && { echo "FAIL no argument must not kill anything"; fail=1; }
echo "ok   no argument is a usage error"

exit $fail
