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
if [ -n "$(unlinked)" ] && [ "$(git -C "$repo" symbolic-ref --short -q HEAD)" != main ]; then
	# The links point into this checkout, so a restow from a feature branch
	# links that branch, and leaves dangling links once it is switched back.
	echo "Not linked into \$HOME, so not loaded in this session - tell me; the checkout is not on main, so \`make -C $repo restow\` is left to me:"
	unlinked
elif [ -n "$(unlinked)" ]; then
	# Sessions started together would otherwise restow together, and two
	# backup.sh runs race to move the same file. mkdir is the lock: the first
	# session restows, the rest wait for it and only check the result. A lock
	# older than two minutes is one a killed hook left behind - past the 60 s
	# hook cap, so a slow restow never has its lock taken from under it.
	lock="${TMPDIR:-/tmp}/session-start-restow.lock"
	find "$lock" -maxdepth 0 -mmin +2 -exec rmdir {} \; 2>/dev/null
	stuck=
	if mkdir "$lock" 2>/dev/null; then
		trap 'rmdir "$lock" 2>/dev/null' EXIT
		trap 'exit 1' INT TERM
		# SESSION_START_RESTOW is the test's seam; nothing else sets it.
		out=$(${SESSION_START_RESTOW:-make -C "$repo" restow} 2>&1)
		rmdir "$lock"
		trap - EXIT INT TERM
	else
		# 10 s, not longer: a lock that outlives a restow (~1 s) is stuck, and
		# every second here comes out of the same 60 s cap.
		for _ in $(seq 10); do [ -d "$lock" ] || break; sleep 1; done
		[ ! -d "$lock" ] || stuck=1
		out=
	fi
	# restow moves aside a real file an app wrote over a link; say which, or a
	# changed setting disappears into a .bak nobody looks at. Only the agent
	# reads this output, so it has to pass it on.
	moved=$(grep -E '^(NOTE|WARNING):' <<<"$out")
	if [ -n "$moved" ]; then
		echo "restow moved these aside at session start - tell me, the app may have written a setting I want in the repo:"
		echo "$moved"
	fi
	missing=$(unlinked)
	if [ -n "$missing" ] && [ -n "$stuck" ]; then
		echo "Not linked into \$HOME, and $lock has been held for over 10 s, so no restow ran - tell me; if no restow is running, remove it and run \`make -C $repo restow\`:"
		echo "$missing"
	elif [ -n "$missing" ]; then
		echo "Not linked into \$HOME even after \`make -C $repo restow\`, so not loaded in this session - tell me:"
		echo "$missing"
		tail -n 5 <<<"$out"
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
