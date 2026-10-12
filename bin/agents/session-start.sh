#!/usr/bin/env bash
# SessionStart hook: what a session has to know before the first prompt.
#
# Whatever this prints goes into the context, but only under Claude Code's
# 10 000-character cap on hook output. Past it the session gets a file path and
# a 2 000-character preview, silently - which is how the brain index stopped
# arriving once it grew past 26 KB.
set -u

repo=$(cd "$(dirname "$0")/../.." && pwd)

# stow links file by file (--no-folding), so a rule or skill merged into the
# repo is read by no harness until `make restow`. From inside a session that
# looks exactly like a rule being ignored, and it shipped that way twice - so
# the session that notices runs it, rather than asking me to.
unlinked() {
	git -C "$repo" ls-files shared/.agents | sed 's|^shared/||' |
		while read -r f; do [ -e "$HOME/$f" ] || echo "  ~/$f"; done
}
# Every message below is for the agent to pass on, so each says what happened
# and what to do in words that need no knowledge of stow or of this script.
branch=$(git -C "$repo" symbolic-ref --short -q HEAD)
if [ -n "$(unlinked)" ] && [ "$branch" != main ]; then
	# The links point into this checkout, so a restow from a feature branch
	# links that branch, and leaves dangling links once it is switched back.
	if [ -n "$branch" ]; then where="branch '$branch'"; else where="a detached HEAD"; fi
	echo "Tell the user, in plain words: some rules and skills from the config repo are not linked into ~/, so this session does not load them."
	echo "They were not linked automatically because $repo is on $where, not on main, and linking from there would point ~/ at that branch's files."
	echo "What to do: switch $repo back to main and start a new session - it links them by itself. Or, to link this branch on purpose, run: make -C $repo restow"
	echo "Not linked:"
	unlinked
elif [ -n "$(unlinked)" ]; then
	# Sessions started together would otherwise restow together, and two
	# backup.sh runs race to move the same file. mkdir is the lock: the first
	# session restows, the rest wait for it and only check the result. A lock
	# older than two minutes is one a killed hook left behind - past the 60 s
	# hook cap, so a slow restow never has its lock taken from under it.
	lock="${TMPDIR:-/tmp}/session-start-restow.lock"
	find "$lock" -maxdepth 0 -mmin +2 -exec rmdir {} \; 2>/dev/null
	stuck='' waited='' held=''
	mkdir "$lock" 2>/dev/null && held=1
	if [ -z "$held" ] && [ -d "$lock" ]; then
		# 10 s, not longer: a lock that outlives a restow (~1 s) is stuck, and
		# every second here comes out of the same 60 s cap.
		for _ in $(seq 10); do [ -d "$lock" ] || break; sleep 1; done
		[ ! -d "$lock" ] || stuck=1
		out='' waited=1
	else
		# No lock and none to wait for means $TMPDIR is missing or read-only:
		# restow without one rather than wait for a session that does not exist.
		# bash runs the EXIT trap on TERM and INT too, once the restow returns.
		[ -z "$held" ] || trap 'rmdir "$lock" 2>/dev/null' EXIT
		# SESSION_START_RESTOW is the test's seam; nothing else sets it.
		out=$(${SESSION_START_RESTOW:-make -C "$repo" restow} 2>&1)
		[ -z "$held" ] || { rmdir "$lock"; trap - EXIT; }
	fi
	# restow moves aside a real file in the way of a link; say which, or a
	# changed setting disappears into a .bak nobody looks at.
	notes=$(grep '^NOTE:' <<<"$out")
	warnings=$(grep '^WARNING:' <<<"$out")
	if [ -n "$notes" ]; then
		echo "Tell the user, in plain words: this session found real files where the config repo keeps its links - an app may have overwritten a link, or the file was there before the repo was set up. It renamed each one to <name>.bak.<time> next to it. Nothing was deleted."
		echo "What to do: compare each .bak file below with the repo's version (in $repo, under shared, devices or os), copy any change worth keeping into the repo, then delete the .bak."
		echo "$notes"
	fi
	if [ -n "$warnings" ]; then
		echo "Tell the user, in plain words: these files are in the way of the config repo's links and could not be moved aside, so they are still not linked."
		echo "What to do: rename each one by hand (add .bak to its name), run make -C $repo restow, then start a new session."
		echo "$warnings"
	fi
	missing=$(unlinked)
	if [ -n "$missing" ] && [ -n "$stuck" ]; then
		echo "Tell the user, in plain words: some rules and skills from the config repo are not linked into ~/, so this session does not load them."
		echo "Another session started linking them and has not finished in 10 s, where it normally takes about a second. It either crashed and left its lock behind, which clears itself after 2 minutes, or it is still running."
		echo "What to do: wait two minutes, then start a new session - it links them by itself. To link them right now instead, and only if no other Claude session is starting at this moment, run: rmdir $lock 2>/dev/null; make -C $repo restow"
		echo "Not linked:"
		echo "$missing"
	elif [ -n "$missing" ] && [ -n "$waited" ]; then
		echo "Tell the user, in plain words: some rules and skills from the config repo are not linked into ~/, so this session does not load them."
		echo "Another session starting at the same time tried to link them and it did not work. The reason went to that session, not this one."
		echo "What to do: run make -C $repo restow to see the error, fix what it says, then start a new session."
		echo "Not linked:"
		echo "$missing"
	elif [ -n "$missing" ]; then
		echo "Tell the user, in plain words: some rules and skills from the config repo are not linked into ~/, so this session does not load them."
		# backup.sh says "now linked" before stow runs, and a stow that fails
		# links nothing at all.
		[ -z "$notes" ] || echo "The files above that were moved aside are probably not linked yet either."
		# make's own Entering/Leaving/Error lines would fill the tail; the cause
		# is in what stow said.
		out=$(grep -Ev '^make(\[[0-9]+\])?: ' <<<"$out")
		if [ -n "$out" ]; then
			echo "This session ran make -C $repo restow to link them, and it did not help. The end of its output is below."
			echo "What to do: fix what that output says (\"stow not installed\" means: run brew install stow), run make -C $repo restow again, then start a new session."
		else
			echo "This session ran make -C $repo restow to link them; it printed nothing and it did not help."
			echo "What to do: run make -C $repo restow yourself and look at what it says, then start a new session."
		fi
		echo "Not linked:"
		echo "$missing"
		[ -z "$out" ] || { echo "restow output:"; tail -n 5 <<<"$out"; }
	fi
fi

f="$HOME/projects/landsman/brain/wiki/index.md"
[ -f "$f" ] || exit 0
# One line per page, without the description that made the file too long.
# ponytail: titles alone overflow the cap too, near 300 pages; split the index by category then.
idx=$(sed -nE '/^## /p; /^- /{s/ — .*//; s/^(- \[[^]]*\]\([^)]*\)).*/\1/; p;}' "$f")
[ "${#idx}" -lt 8000 ] || idx=$(sed -nE '/^## /p; /^- /{s/ — .*//; s/^- \[([^]]*)\].*/- \1/; p;}' "$f")
echo "Brain index, titles only - $f says what each page holds. Check it before researching; load the brain skill to read or write it."
echo "$idx"
