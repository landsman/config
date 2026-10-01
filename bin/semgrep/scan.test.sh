#!/usr/bin/env bash
# The decisions scan.sh makes before Docker is involved: which version, and
# which targets and flags. No network, no Docker.
set -euo pipefail
scan=$(cd "$(dirname "$0")" && pwd)/scan.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL  $*" >&2; exit 1; }

printf '# a comment\nFROM semgrep/semgrep:1.172.0\nLABEL x=y\n' >"$tmp/Dockerfile"
[ "$("$scan" version "$tmp/Dockerfile")" = 1.172.0 ] || fail "version from FROM"
printf 'FROM semgrep/semgrep\n' >"$tmp/Dockerfile"
! "$scan" version "$tmp/Dockerfile" 2>/dev/null || fail "a FROM with no version is an error"

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

(cd "$tmp/repo" && SCAN_PATH=nope "$scan" args >/dev/null 2>&1) && fail "a missing path is an error"
echo "ok    semgrep scan.sh"
