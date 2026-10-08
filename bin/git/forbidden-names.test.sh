#!/usr/bin/env bash
# Self-check for ./forbidden-names.sh: throwaway repos under a throwaway $HOME,
# a made-up owner, and the script run the way git runs it.
set -eu

hook="$(cd "$(dirname "$0")" && pwd)/forbidden-names.sh"
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
fails=0

check() { # check <name> <expected exit> <command...>
	local name=$1 want=$2; shift 2
	local got=0; "$@" >/dev/null 2>&1 || got=$?
	if [ "$got" = "$want" ]; then echo "ok   $name"; else echo "FAIL $name (exit $got, want $want)"; fails=$((fails + 1)); fi
}
refuse() { # refuse <name> <command...>: exit 1 with the hook's own message, not a crash
	local name=$1 out got=0; shift
	out=$("$@" 2>&1 >/dev/null) || got=$?
	if [ "$got" = 1 ] && [[ $out == *"belongs to another owner"* ]]; then echo "ok   $name"; else echo "FAIL $name (exit $got, not refused by the hook)"; fails=$((fails + 1)); fi
}

export HOME="$tmp" GIT_CONFIG_GLOBAL="$tmp/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@t
git config --global user.name t
git config --global commit.gpgsign false
printf '# owner regex\nacme acme|acme-bot\n' > "$tmp/names"

repo() { mkdir -p "$1" && git -C "$1" init -q && cd "$1"; }
stage() { echo "$1" > f.txt && git add f.txt; }

repo "$tmp/projects/landsman/public"
check "unset key: nothing to check" 0 "$hook"
git config --global forbiddenNames.file "$tmp/names"

stage "org=\${ORG:?set ORG}"
check "clean diff passes" 0 "$hook"
stage "org=\${ORG:-ACME}"
refuse "staged name refused, any case" "$hook"
check "the hit names file and line" 0 sh -c "'$hook' 2>&1 | grep -q 'f.txt:1: org='"
printf 'fe: fix the footer\n# acme in git'"'"'s template\n' > msg
check "clean message passes, comments ignored" 0 "$hook" msg
echo "be: deploy for acme" > msg
refuse "message naming it refused" "$hook" msg
printf 'fix: drop the name\n# ------------------------ >8 ------------------------\n# Do not modify or remove the line above.\ndiff --git a/f.txt b/f.txt\n-org=acme\n' > msg
check "commit -v: the diff below the scissors is not the message" 0 "$hook" msg
refuse "stdin, for a PR body" sh -c "echo 'the acme-bot account' | '$hook' -"
refuse "stdin: a Markdown heading is text, not a comment" sh -c "printf '# Deploy for acme\\nbody\\n' | '$hook' -"
git rm -q --cached f.txt && : > acme-deploy.sh && git add acme-deploy.sh
refuse "an empty file named after it" "$hook"
git rm -q --cached acme-deploy.sh && printf 'one\n++ acme\n' > f.txt && git add f.txt
refuse "an added line starting with ++ is not a header" "$hook"
git rm -q --cached f.txt && stage "clean"
printf 'other   \nacme acme\r\n' > "$tmp/names"
check "an owner with no pattern does not match everything" 0 "$hook"
printf '# owner regex\nacme acme|acme-bot\n' > "$tmp/names"

repo "$tmp/projects/acme/backend"
stage "org=acme"
check "the owner's own repo may name it" 0 "$hook"
git commit -qm init && git worktree add -q "$tmp/wt" 2>/dev/null
cd "$tmp/wt" && stage "org=acme"
check "…also from a worktree outside ~/projects" 0 "$hook"

printf 'holding,acme acme\n' > "$tmp/names"
repo "$tmp/projects/holding/app"
stage "org=acme"
check "a name listed for several owners passes in each" 0 "$hook"
repo "$tmp/projects/acmez/app"
stage "org=acme"
refuse "…and an owner whose folder only starts the same is not one of them" "$hook"
printf '# owner regex\nacme acme|acme-bot\n' > "$tmp/names"

repo "$tmp/projects/landsman/brain"
mv "$tmp/names" names && git config --global forbiddenNames.file "$PWD/names"
stage "acme is a client"
check "the repo holding the list is exempt" 0 "$hook"
repo "$tmp/projects/landsman/other"
rm "$tmp/projects/landsman/brain/names"
check "missing list refuses" 1 "$hook"

# The wiring in .gitconfig, through git itself (config hooks need git 2.54+).
if git hook list pre-commit >/dev/null 2>&1 || git help config 2>/dev/null | grep -q 'hook.<friendly-name>'; then
	echo "acme acme" > "$tmp/names" && git config --global forbiddenNames.file "$tmp/names"
	git config --global hook.forbidden-names.command "$hook"
	git config --global --add hook.forbidden-names.event pre-commit
	git config --global --add hook.forbidden-names.event commit-msg
	stage "nothing to see"
	refuse "git runs it on commit-msg" git commit -qm "for acme"
	refuse "git runs it on pre-commit" sh -c "echo acme > f.txt && git add f.txt && git commit -qm clean"
else
	echo "skip config-hook wiring (git $(git --version | cut -d' ' -f3) is older than 2.54)"
fi

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
