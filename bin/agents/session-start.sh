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
# looks exactly like a rule being ignored, and it shipped that way twice.
missing=$(git -C "$repo" ls-files shared/.agents | sed 's|^shared/||' |
	while read -r f; do [ -e "$HOME/$f" ] || echo "  ~/$f"; done)
if [ -n "$missing" ]; then
	echo "Not linked into \$HOME, so not loaded in this session - tell me; \`make -C $repo restow\` links them:"
	echo "$missing"
fi

f="$HOME/projects/landsman/brain/wiki/index.md"
[ -f "$f" ] || exit 0
# One line per page, without the description that made the file too long.
# ponytail: titles alone overflow the cap too, near 300 pages; split the index by category then.
idx=$(sed -nE '/^## /p; /^- /{s/ — .*//; s/^(- \[[^]]*\]\([^)]*\)).*/\1/; p;}' "$f")
[ "${#idx}" -lt 8000 ] || idx=$(sed -nE '/^## /p; /^- /{s/ — .*//; s/^- \[([^]]*)\].*/- \1/; p;}' "$f")
echo "Brain index, titles only - $f says what each page holds. Check it before researching; load the brain skill to read or write it."
echo "$idx"
