#!/usr/bin/env bash
# The decision scan.sh makes before Docker is involved: which targets and
# flags. The version is bin/mirror/image.sh's, tested there. No network, no Docker.
set -euo pipefail
scan=$(cd "$(dirname "$0")" && pwd)/scan.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL  $*" >&2; exit 1; }

# One directory of a monorepo: that directory, and .github beside it.
mkdir -p "$tmp/repo/app" "$tmp/repo/.github"
got=$(cd "$tmp/repo" && BASE_PACKS="p/secrets p/ci" PACKS=p/typescript SCAN_PATH=app \
  EXCLUDES=app/dist EXCLUDE_RULES=some.rule "$scan" args)
want='--config=p/secrets
--config=p/ci
--config=p/typescript
--exclude=app/dist
--exclude-rule=some.rule
--metrics=off
--error
app
.github'
[ "$got" = "$want" ] || fail "args for a directory: got
$got"

# The whole repo already includes .github — not named twice.
got=$(cd "$tmp/repo" && SCAN_PATH=. "$scan" args | tail -1)
[ "$got" = . ] || fail "the whole repo ends at ., got $got"

# No SCAN_PATH: the whole repo.
got=$(cd "$tmp/repo" && "$scan" args | tail -1)
[ "$got" = . ] || fail "no SCAN_PATH scans ., got $got"

# A repo with no .github gets no .github target.
mkdir -p "$tmp/bare/app"
got=$(cd "$tmp/bare" && SCAN_PATH=app "$scan" args | tail -1)
[ "$got" = app ] || fail "no .github, no .github target, got $got"

# A pattern reaches semgrep as written, not expanded against this directory.
touch "$tmp/repo/package.lock"
got=$(cd "$tmp/repo" && EXCLUDES='*.lock' SCAN_PATH=. "$scan" args | grep -- --exclude=)
[ "$got" = '--exclude=*.lock' ] || fail "exclude globbed into $got"

(cd "$tmp/repo" && SCAN_PATH=nope "$scan" args >/dev/null 2>&1) && fail "a missing path is an error"
echo "ok    semgrep scan.sh"
