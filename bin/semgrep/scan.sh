#!/usr/bin/env bash
# The scan the shared semgrep workflow runs (.github/workflows/semgrep.yml),
# from the root of the repository being scanned.
#
#   scan.sh scan <Dockerfile>   pull the pinned image (bin/mirror/image.sh) and scan
#   scan.sh args                semgrep's arguments, one per line
#
# Input comes from the environment, never the command line, because these are
# strings another repo's workflow supplies: BASE_PACKS, PACKS, SCAN_PATH,
# EXCLUDES, BASE_EXCLUDE_RULES, EXCLUDE_RULES — each space-separated.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)

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
  local image list line
  list=$(args)
  image=$("$here/../mirror/image.sh" pull semgrep "$1")
  local -a a=()
  while IFS= read -r line; do a+=("$line"); done <<<"$list"
  docker run --rm -v "$PWD:/src" -w /src "$image" semgrep "${a[@]}"
}

case ${1:-} in
  scan) scan "${2:?Dockerfile}" ;;
  args) args ;;
  *) sed -n '2,10p' "$0" >&2; exit 2 ;;
esac
