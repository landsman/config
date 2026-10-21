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
# repo is read by no harness until it is linked. From inside a session that
# looks exactly like a rule being ignored, and it shipped that way twice - so
# the session that notices links it, rather than asking me to.
unlinked() {
	# -z: without it git quotes a name with a non-ASCII letter, which then
	# never resolves and reads as unlinked forever.
	git -C "$repo" ls-files -z shared/.agents | while IFS= read -r -d '' f; do
		f=${f#shared/}
		# stow's built-in ignore list never links these, so they never resolve.
		case ${f##*/} in .gitignore | .cvsignore | *~ | \#*\# | .\#*) continue ;; esac
		[ -e "$HOME/$f" ] || echo "  ~/$f"
	done
}

# Every message is for the agent to relay in plain words: what happened, then
# what the user can do. The commands in them are the user's to run.
links() {
	# lock is not local: the EXIT trap reads it.
	local before after linked branch where out='' rc=0 held='' stuck='' waited=''
	before=$(unlinked)
	[ -n "$before" ] || return 0
	branch=$(git -C "$repo" symbolic-ref --short -q HEAD)
	if [ "$branch" != main ]; then
		# The links point into this checkout, so linking from a feature branch
		# links that branch, and leaves dangling links once it is switched back.
		if [ -n "$branch" ]; then where="branch '$branch'"; else where="a detached HEAD"; fi
		echo "Tell the user, in plain words: some rules and skills from the config repo are not linked into ~/, so this session does not load them."
		echo "They were not linked automatically because $repo is on $where, not on main, and linking from there would point ~/ at that branch's files."
		echo "What the user can do: switch $repo back to main, run make -C $repo restow, then start a new session. (To link this branch on purpose, run the same while on it.)"
		echo "Not linked:"
		echo "$before"
		return 0
	fi
	# Sessions started together would otherwise link together. mkdir is the
	# lock: the first session links, the rest wait for it and only check the
	# result. A lock older than two minutes is one a killed hook left behind -
	# past the 60 s timeout settings.json gives this hook, so a slow run never
	# has its lock taken from under it.
	lock="${TMPDIR:-/tmp}/session-start-restow.lock"
	find "$lock" -maxdepth 0 -mmin +2 -exec rmdir {} \; 2>/dev/null
	mkdir "$lock" 2>/dev/null && held=1
	if [ -z "$held" ] && [ -d "$lock" ]; then
		# 10 s, not longer: a lock that outlives a run (~1 s) is stuck, and every
		# second here delays the session.
		for _ in $(seq 10); do [ -d "$lock" ] || break; sleep 1; done
		[ ! -d "$lock" ] || stuck=1
		waited=1
	else
		# No lock and none to wait for means $TMPDIR is missing or read-only:
		# link without one rather than wait for a session that does not exist.
		# bash runs the EXIT trap on TERM and INT too, once the link returns.
		[ -z "$held" ] || trap 'rmdir "$lock" 2>/dev/null' EXIT
		# relink, not restow: unattended, a real file in the way stops it rather
		# than being renamed to a .bak nobody looks at.
		# SESSION_START_RESTOW is the test's seam; nothing else sets it.
		out=$(${SESSION_START_RESTOW:-make -C "$repo" relink} 2>&1) || rc=$?
		[ -z "$held" ] || { rmdir "$lock"; trap - EXIT; }
	fi
	after=$(unlinked)
	linked=$(comm -23 <(sort <<<"$before") <(sort <<<"$after") | grep .)
	if [ -n "$linked" ]; then
		# Rules load in parallel with this hook, not after it, so whatever it
		# links reaches the next session only.
		echo "Tell the user, in plain words: these rules and skills from the config repo were linked into ~/ just now, but this session had already loaded its rules, so it runs without them."
		echo "What the user can do: start a new session to load them."
		echo "Linked just now:"
		echo "$linked"
	fi
	[ -n "$after" ] || return 0
	echo "Tell the user, in plain words: some rules and skills from the config repo are not linked into ~/, so this session does not load them."
	if [ -n "$stuck" ]; then
		echo "Another session started linking them and has not finished in 10 s, where it normally takes about a second. It either crashed and left its lock behind, which clears itself after 2 minutes, or it is still running."
		echo "What the user can do: wait two minutes, then run make -C $repo restow in a terminal and start a new session. Right away instead, if no other Claude session is starting at this moment: rmdir $lock 2>/dev/null; make -C $repo restow"
	elif [ -n "$waited" ]; then
		echo "Another session starting at the same time tried to link them and it did not work. The reason went to that session, not this one."
		echo "What the user can do: run make -C $repo restow in a terminal and read what it says, then start a new session."
	else
		if [ "$rc" -ne 0 ]; then
			echo "This session tried to link them and it failed - most often because a real file sits where a link should go, for example after an app saved over one. It moves nothing aside on its own, so nothing was renamed or lost."
		else
			echo "This session tried to link them; it reported no error, yet these are still not linked."
		fi
		echo "What the user can do: run make -C $repo restow in a terminal. It renames any file in the way to <name>.bak.<time>, links the repo's version and says which files it renamed; compare each .bak with the repo and keep what is worth keeping. Then start a new session."
	fi
	echo "Not linked:"
	echo "$after"
	# make's own Entering/Leaving/Error lines would fill the tail; the cause is
	# in what stow said.
	out=$(grep -Ev '^make(\[[0-9]+\])?: ' <<<"$out")
	[ -z "$out" ] || { echo "Output of the failed attempt:"; tail -n 5 <<<"$out"; }
}
msg=$(links)
[ -z "$msg" ] || echo "$msg"

f="$HOME/projects/landsman/brain/wiki/index.md"
[ -f "$f" ] || exit 0
# One line per page, without the description that made the file too long. The
# budget leaves room for what links printed above, under the same cap.
# ponytail: titles alone overflow the cap too, near 300 pages; split the index by category then.
idx=$(sed -nE '/^## /p; /^- /{s/ — .*//; s/^(- \[[^]]*\]\([^)]*\)).*/\1/; p;}' "$f")
[ "${#idx}" -lt $((8000 - ${#msg})) ] || idx=$(sed -nE '/^## /p; /^- /{s/ — .*//; s/^- \[([^]]*)\].*/- \1/; p;}' "$f")
echo "Brain index, titles only - $f says what each page holds. Check it before researching; load the research-brain skill to read or write it."
echo "$idx"
