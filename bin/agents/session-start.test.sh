#!/usr/bin/env bash
# Self-check for ./session-start.sh: a throwaway $HOME, and a throwaway repo
# holding the hook and the real shared/.agents, so the test picks its branch.
set -eu

dir="$(cd "$(dirname "$0")" && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
export HOME="$tmp" TMPDIR="$tmp"
repo="$tmp/repo"
hook="$repo/bin/agents/session-start.sh"
mkdir -p "$repo/bin/agents" "$repo/shared"
cp "$dir/session-start.sh" "$repo/bin/agents/"
cp -R "$dir/../../shared/.agents" "$repo/shared/"
# Two names the real tree may grow: one git quotes, one stow never links.
echo x > "$repo/shared/.agents/rules/příklad.md"
echo x > "$repo/shared/.agents/skills/.gitignore"
git -C "$repo" init -q -b main
git -C "$repo" add .
git -C "$repo" -c user.name=t -c user.email=t@t commit -qm t

run() { last=$(bash "$hook"); } # run the hook once, for several expects
expect() { # expect <name> <substring> <yes|no>: is the substring in the last run?
	if { [ "$3" = yes ] && [[ "$last" == *"$2"* ]]; } || { [ "$3" = no ] && [[ "$last" != *"$2"* ]]; }; then
		echo "ok   $1"
	else
		echo "FAIL $1"; echo "  got: $last"; fails=$((fails + 1))
	fi
}
check() { run; expect "$@"; }
lock="$tmp/session-start-restow.lock"
rule=".agents/rules/attribution.md"
# Fakes for `make relink`. Each leaves $tmp/ran behind, so a test can tell
# whether it ran without relying on what the hook chose to print.
# mark: links nothing.
printf '#!/bin/sh\ntouch "%s/ran"\n' "$tmp" > "$tmp/mark"
# link-all: links every file as stow would - the .gitignore left out - and
# says so on stderr, where stow speaks.
cat > "$tmp/link-all" <<EOF
#!/usr/bin/env bash
touch "$tmp/ran"
cd "$repo/shared" && find .agents -type f ! -name .gitignore | while IFS= read -r f; do
	mkdir -p "\$HOME/\$(dirname "\$f")"; ln -sf "\$PWD/\$f" "\$HOME/\$f"
done
echo "linked everything" >&2
EOF
# fail: what a real failed relink prints - make's lines on stdout around
# stow's own error on stderr - and its exit code.
cat > "$tmp/fail" <<EOF
#!/bin/sh
touch "$tmp/ran"
echo "make: Entering directory /r"
echo "stow: ERROR: conflicts" >&2
echo "make: *** [relink] Error 2"
echo "make: Leaving directory /r"
exit 2
EOF
chmod +x "$tmp/mark" "$tmp/link-all" "$tmp/fail"
ran() { # ran <name> <yes|no>: did the fake run since the last call?
	local r=no; [ ! -e "$tmp/ran" ] || r=yes
	rm -f "$tmp/ran"
	if [ "$r" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (ran: $r)"; fails=$((fails + 1)); fi
}

export SESSION_START_RESTOW="$tmp/mark"
git -C "$repo" checkout -q -b feature
run
ran "off main, nothing run" no
expect "off main, the unlinked rule is named" "$rule" yes
expect "and the branch is named" "is on branch 'feature', not on main" yes
git -C "$repo" checkout -q --detach
check "a detached HEAD is called that" "is on a detached HEAD, not on main" yes
git -C "$repo" checkout -q main
rm -f "$tmp/ran"

run
ran "on main, relink runs" yes
expect "it linked nothing, said as such" "it reported no error, yet these are still not linked" yes
expect "the rule is named" "$rule" yes
expect "no output, none shown" "Output of the failed attempt" no
expect "no brain, no index" "Brain index" no

export SESSION_START_RESTOW="$tmp/fail"
run
ran "a failing relink runs" yes
expect "its failure is said" "it failed - most often because a real file" yes
expect "stow's error on stderr is shown" "stow: ERROR: conflicts" yes
expect "make's lines around it are not" "make: " no
expect "the fix is restow, run by the user" "run make -C $repo restow in a terminal" yes

export SESSION_START_RESTOW="$tmp/link-all"
run
ran "relink runs" yes
expect "what it linked is named" "Linked just now:" yes
expect "with the rule" "$rule" yes
expect "and a new session is asked for" "start a new session to load them" yes
expect "nothing is left unlinked - the quoted name and the ignored file included" "Not linked" no
check "linked already, nothing to say" "Linked just now" no
ran "and nothing runs" no
rm -rf "$tmp/.agents"

export SESSION_START_RESTOW="$tmp/mark"
TMPDIR="$tmp/nope" run
ran "no usable \$TMPDIR, relink runs without a lock" yes
expect "and no other session is blamed" "Another session" no
[ ! -e "$tmp/nope" ] && [ ! -e "$lock" ] || { echo "FAIL no usable \$TMPDIR, yet a lock was made"; fails=$((fails + 1)); }

mkdir "$lock"
# The other session links everything before it lets go: a hook that did not
# wait would still see the rules unlinked.
(sleep 1; "$tmp/link-all" 2>/dev/null; rm -f "$tmp/ran"; rmdir "$lock") &
run
ran "another session holds the lock, nothing run twice" no
expect "this one waited, and says what that session linked" "Linked just now:" yes
expect "and asks for a new session" "start a new session to load them" yes
rm -rf "$tmp/.agents"

mkdir "$lock"
# 90 s old: stale at one minute, still live at two.
perl -e 'utime undef, time - 90, shift' "$lock"
run
ran "a stuck lock: nothing run while it is held" no
expect "it is waited out and named" "has not finished in 10 s" yes
expect "without claiming it crashed" "or it is still running" yes
expect "with what is unlinked" "$rule" yes
rmdir "$lock"

mkdir "$lock"
(sleep 1; rmdir "$lock") &
run
ran "another session's attempt failed: nothing run here" no
expect "said as such" "The reason went to that session" yes
expect "with what is unlinked" "$rule" yes

mkdir "$lock"
# 150 s old: past the two minutes, so cleared.
perl -e 'utime undef, time - 150, shift' "$lock"
run
ran "a stale lock is cleared, relink runs" yes
[ ! -d "$lock" ] || { echo "FAIL the lock is left behind"; fails=$((fails + 1)); rmdir "$lock"; }

# A hook killed mid-run lets go of the lock on its way out. Claude Code
# signals the hook's whole process group, so the test does too: set -m gives
# the background job a group of its own. bash runs the EXIT trap only once the
# command it waits on returns, hence the wait.
export SESSION_START_RESTOW="sleep 2"
for sig in TERM INT; do
	set -m; bash "$hook" >/dev/null & pid=$!; set +m
	sleep 1
	[ -d "$lock" ] || { echo "FAIL the hook to be killed by $sig holds no lock"; fails=$((fails + 1)); }
	kill -"$sig" -- -"$pid"; wait "$pid" 2>/dev/null || true
	# The trap runs in the subshell that holds the lock, which can outlive
	# the hook's own process by a moment.
	for _ in 1 2 3 4 5 6 7 8 9 10; do [ -d "$lock" ] || break; sleep 0.2; done
	if [ -d "$lock" ]; then echo "FAIL a hook killed by $sig leaves the lock behind"; fails=$((fails + 1)); rmdir "$lock"
	else echo "ok   a hook killed by $sig lets go of the lock"; fi
done

export SESSION_START_RESTOW="$tmp/link-all"
bash "$hook" >/dev/null; rm -f "$tmp/ran"
check "everything linked, nothing to say" "Tell the user" no
ran "and nothing runs" no

mkdir -p "$tmp/projects/landsman/brain/wiki"
idx="$tmp/projects/landsman/brain/wiki/index.md"
printf '# Index\n\n## Tools\n\n- [Page](page.md) — what the page holds\n- Not written yet — why it would be\n' > "$idx"
check "the index keeps the title and link" "- [Page](page.md)" yes
check "and drops the description" "what the page holds" no
check "a page with no link keeps its title" "- Not written yet" yes

for i in $(seq 300); do echo "- [A page title number $i](a-page-title-number-$i.md) — d"; done >> "$idx"
check "a long index falls back to titles" "- A page title number 300" yes
check "without the links" "(a-page-title-number-300.md)" no

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
