#!/usr/bin/env bash
# Self-contained: a throwaway repo with a remote, a submodule and one worktree
# per case, swept with the idle clock at zero, then checked for what is left.
set -euo pipefail
sweep="$(cd "$(dirname "$0")" && pwd)/worktree-sweep.sh"
t=$(mktemp -d)
pid=
trap '[ -z "$pid" ] || kill "$pid" 2>/dev/null; rm -rf "$t"' EXIT
# Global signing or a global hook must not decide whether this passes.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
g() { git -c user.name=t -c user.email=t@t -c protocol.file.allow=always "$@"; }

g init -q --bare -b main "$t/sub.git"
g clone -q "$t/sub.git" "$t/sub" 2>/dev/null
g -C "$t/sub" commit -q --allow-empty -m init && g -C "$t/sub" push -q origin main
g init -q --bare -b main "$t/origin.git"
g clone -q "$t/origin.git" "$t/r" 2>/dev/null
r=$(cd "$t/r" && pwd -P) wt=$(cd "$t/r" && pwd -P)/.claude/worktrees
g -C "$r" submodule -q add "$t/sub.git" sub
g -C "$r" commit -qm init && g -C "$r" push -q origin main

new() { g -C "$r" worktree add -q "$wt/$1" -b "$1" main; }
pushed() { new "$1" && g -C "$wt/$1" push -q -u origin "$1" 2>/dev/null; }

pushed clean && g -C "$wt/clean" submodule -q update --init
pushed dirty && touch "$wt/dirty/x"
new unpushed && g -C "$wt/unpushed" commit -q --allow-empty -m wip
pushed gone && g -C "$wt/gone" commit -q --allow-empty -m squashed-away && g -C "$wt/gone" push -q 2>/dev/null
g -C "$r" push -q origin --delete gone 2>/dev/null && g -C "$r" fetch -q --prune
pushed locked && g -C "$r" worktree lock "$wt/locked"
# disown: bash would report the kill at exit as a "Terminated" line.
pushed busy && { (cd "$wt/busy" && exec sleep 60) & pid=$! && disown; }
g -C "$r" worktree add -q "$t/elsewhere" -b elsewhere main
# All of the above can take less than a second, and find counts the current
# second as within -mmin -0, so whether a case looked idle was down to the
# clock. Dated back, the reflog alone says how old they are.
touch -t 202001010000 "$r"/.git/worktrees/*/HEAD "$r"/.git/worktrees/*/index

fail=0
check() { # want name
	if [ -d "$wt/$2" ] || [ -d "$t/$2" ]; then got=kept; else got=removed; fi
	if [ "$got" = "$1" ]; then echo "ok   $1 $2"; else echo "FAIL want $1, got $got: $2"; fail=1; fi
}

bash "$sweep" "$r" >/dev/null
check kept clean # under a day old

WORKTREE_SWEEP_IDLE_MINUTES=0 bash "$sweep" --list "$r" >/dev/null
check kept clean # --list removes nothing

# The hook acts on a new worktree only, and never fails the git command.
WORKTREE_SWEEP_IDLE_MINUTES=0 bash "$sweep" --hook "$(g -C "$r" rev-parse HEAD)" x 1 2>/dev/null || fail=1
check kept clean # a plain checkout
(cd "$t" && bash "$sweep" --hook 0000000000000000000000000000000000000000 x 1) || { echo "FAIL hook exit code outside a repo"; fail=1; }

# A process list that comes back empty, or from a failed lsof, is no list:
# nothing goes on a guess, and the sweep says why it did nothing.
mkdir "$t/bin"
for fake in '' 'echo n/nowhere; exit 1'; do
	printf '#!/bin/sh\n%s\n' "$fake" >"$t/bin/lsof" && chmod +x "$t/bin/lsof"
	err=$(PATH="$t/bin:$PATH" WORKTREE_SWEEP_IDLE_MINUTES=0 bash "$sweep" "$r" 2>&1 >/dev/null)
	check kept clean # lsof: ${fake:-empty}
	[ -n "$err" ] || { echo "FAIL no word when lsof gives no list: ${fake:-empty}"; fail=1; }
done

(cd "$wt/dirty" && WORKTREE_SWEEP_IDLE_MINUTES=0 bash "$sweep" --hook 0000000000000000000000000000000000000000 x 1 2>/dev/null)
check removed clean # with a submodule checked out, which git refuses without --force
check kept dirty
check kept unpushed
check removed gone # merged and deleted: its last commit is on no remote any more
check kept locked
check kept busy
check kept elsewhere
g -C "$r" rev-parse -q --verify refs/heads/clean >/dev/null || { echo "FAIL the branch went with the worktree"; fail=1; }

exit $fail
