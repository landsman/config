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
# A restow that links everything and prints its arguments, so what the hook
# says about them cannot come from the "did not help" message's tail.
fake="$tmp/fake-restow"
printf '#!/bin/sh\nln -s "%s" "%s"\necho "$*"\n' "$repo/shared/.agents" "$tmp/.agents" > "$fake"
chmod +x "$fake"

export SESSION_START_RESTOW="echo NOTE: restow ran"
git -C "$repo" checkout -q -b feature
run
expect "off main, restow not run" "restow ran" no
expect "off main, the unlinked rule is named" "$rule" yes
expect "and the branch is named" "is on branch 'feature', not on main" yes
git -C "$repo" checkout -q --detach
check "a detached HEAD is called that" "is on a detached HEAD, not on main" yes
git -C "$repo" checkout -q main

export SESSION_START_RESTOW=true
run
expect "a rule restow could not link is named" "$rule" yes
expect "after restow ran and printed nothing" "it printed nothing and it did not help" yes
expect "no brain, no index" "Brain index" no
export SESSION_START_RESTOW="echo boom"
run
expect "restow failed, its output is shown" "boom" yes
expect "and pointed at" "The end of its output is below" yes
export SESSION_START_RESTOW="echo NOTE: ~/x was a real file"
check "a moved file is doubted when restow then failed" "probably not linked yet either" yes

export SESSION_START_RESTOW="ln -s $repo/shared/.agents $tmp/.agents"
check "restow linked it, nothing to say" "Not linked" no
rm "$tmp/.agents"
export SESSION_START_RESTOW="$fake NOTE: ~/x was a real file"
run
expect "a file restow moved aside is named" "NOTE: ~/x" yes
expect "and explained" "found real files where the config repo keeps its links" yes
expect "and not as a failure" "did not help" no
rm "$tmp/.agents"
export SESSION_START_RESTOW="$fake WARNING: could not back up ~/y"
run
expect "a file restow could not move aside is named" "WARNING: could not back up ~/y" yes
expect "and said to be still in the way" "could not be moved aside" yes
expect "and not as moved" "found real files" no
rm "$tmp/.agents"

export SESSION_START_RESTOW="echo NOTE: restow ran"
TMPDIR="$tmp/nope" run
expect "no usable \$TMPDIR, restow runs without a lock" "restow ran" yes
expect "and no other session is blamed" "Another session" no

mkdir "$lock"
# The other session links the rules before it lets go: a hook that did not
# wait would still see them unlinked.
(sleep 1; ln -s "$repo/shared/.agents" "$tmp/.agents"; rmdir "$lock") &
run
expect "another session holds the lock, restow not run twice" "restow ran" no
expect "and this one waited for it" "Not linked" no
rm "$tmp/.agents"
mkdir "$lock"
# 90 s old: stale at one minute, still live at two.
perl -e 'utime undef, time - 90, shift' "$lock"
run
expect "a stuck lock is waited out and named, restow not run" "has not finished in 10 s" yes
expect "with what is unlinked" "$rule" yes
rmdir "$lock"
mkdir "$lock"
(sleep 1; rmdir "$lock") &
run
expect "another session's restow failed, said as such" "The reason went to that session" yes
expect "with what is unlinked" "$rule" yes

# A hook killed mid-restow lets go of the lock on its way out. bash runs the
# trap only once the restow it waits on returns, hence the wait.
export SESSION_START_RESTOW="sleep 2"
bash "$hook" >/dev/null & pid=$!
sleep 1; kill -TERM "$pid"; wait "$pid" 2>/dev/null || true
[ ! -d "$lock" ] || { echo "FAIL a killed hook leaves the lock behind"; fails=$((fails + 1)); rmdir "$lock"; }
export SESSION_START_RESTOW="echo NOTE: restow ran"
mkdir "$lock"
touch -t 202001010000 "$lock"
check "a stale lock is cleared, restow runs" "restow ran" yes
[ ! -d "$lock" ] || { echo "FAIL the lock is left behind"; fails=$((fails + 1)); }
ln -s "$repo/shared/.agents" "$tmp/.agents"
check "everything linked, restow not run" "restow ran" no

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
