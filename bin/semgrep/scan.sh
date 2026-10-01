#!/usr/bin/env bash
# The scan the shared semgrep workflow runs (.github/workflows/semgrep.yml),
# from the root of the repository being scanned.
#
#   scan.sh scan <Dockerfile>      pull the pinned image and scan
#   scan.sh version <Dockerfile>   the semgrep version the mirror pins
#   scan.sh args                   semgrep's arguments, one per line
#
# Input comes from the environment, never the command line, because these are
# strings another repo's workflow supplies: BASE_PACKS, PACKS, SCAN_PATH,
# EXCLUDES, BASE_EXCLUDE_RULES, EXCLUDE_RULES — each space-separated.
set -euo pipefail

# The FROM line of the mirror's Dockerfile is the one place the version lives,
# and the line Dependabot bumps.
version() {
  local v
  v=$(sed -n 's|^FROM semgrep/semgrep:||p' "$1")
  [ -n "$v" ] || { echo "no FROM semgrep/semgrep:<version> in $1" >&2; exit 1; }
  echo "$v"
}

args() {
  local p e r
  # Split the lists on spaces, but never glob them: an exclude of '*.lock'
  # has to reach semgrep as written, not as the lock files in this directory.
  set -f
  # Baseline first, caller second. A pack named twice costs nothing — semgrep
  # loads it once and reports each finding once.
  for p in ${BASE_PACKS:-} ${PACKS:-}; do echo "--config=$p"; done
  for e in ${EXCLUDES:-}; do echo "--exclude=$e"; done
  for r in ${BASE_EXCLUDE_RULES:-} ${EXCLUDE_RULES:-}; do echo "--exclude-rule=$r"; done
  echo --metrics=off
  # --error turns findings into a failed job; without it semgrep reports and
  # exits 0, which is a check that cannot fail.
  echo --error
  local path=${SCAN_PATH:-.}
  test -d "$path" || { echo "path not in this repo: $path" >&2; exit 1; }
  echo "$path"
  # .github/ sits at the repo root, so a caller scanning one directory of a
  # monorepo would never reach the files p/ci is here for. Scan it too, and
  # accept that four callers in one monorepo each report the same root-level
  # finding — four red checks with one cause reads fine, a silent gap does not.
  [ "$path" = . ] || [ ! -d .github ] || echo .github
}

scan() {
  local v image list line
  v=$(version "$1")
  list=$(args)
  # A version, not `latest`: the log says which semgrep ran, and a tag that only
  # moves with a bump is one a cache can key on. Right after a bump the mirror
  # can lack the new tag for a minute; Docker Hub stands in, as it does for
  # `make security`.
  image=ghcr.io/landsman/semgrep-mirror:$v
  docker pull -q "$image" || { echo "$image not mirrored yet - using docker hub"; image=semgrep/semgrep:$v; }
  local -a a=()
  while IFS= read -r line; do a+=("$line"); done <<<"$list"
  docker run --rm -v "$PWD:/src" -w /src "$image" semgrep "${a[@]}"
}

case ${1:-} in
  scan | version) "$1" "${2:?Dockerfile}" ;;
  args) args ;;
  *) sed -n '2,11p' "$0" >&2; exit 2 ;;
esac
