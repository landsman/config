#!/usr/bin/env bash
# Known vulnerabilities in what is installed on this machine — `make audit`.
#
#   check.sh                  every source, at or above SEVERITY (default high)
#   check.sh brew-findings    read `brew vulns --json` on stdin, one line per formula
#
# Exit 0: every source was checked and found nothing. Exit 1: a finding, a
# source whose answer could not be read, or no source checked at all. Exit 2:
# usage — an unknown argument or a SEVERITY that is not low, medium, high or
# critical. It fails closed: an answer that is not exactly the expected shape
# is a failure, never a pass, because a check that passes when it could not
# look is worse than none.
#
# One function per source of installed software; a source whose tool is not on
# this machine is skipped and says so. Adding one is a function and a line in
# main. A repo's lockfiles are not here — the shared dependencies workflow
# reads those in CI. This is what a laptop actually runs.
set -euo pipefail

severity=${SEVERITY:-high}

# The shape is checked before anything is printed: a renamed key, an error
# object or a null list is a failure, not "nothing found". Fields are printed
# with control characters replaced, because the advisory ids come from OSV —
# remote data — and a terminal escape in one could rewrite the lines around it.
# Slurped, so the answer has to be exactly one JSON document: nothing at all,
# two of them or half of one is a failure too.
brew_findings() {
  jq -r -s '
    def clean: tostring | explode | map(if . < 32 or . == 127 then 63 else . end) | implode;
    if length == 1 and (.[0] | type) == "object" and (.[0].findings | type) == "array"
       and all(.[0].findings[]; (.vulnerabilities | type) == "array")
    then .[0].findings[] | "\(.formula | clean) \(.version | clean): \([.vulnerabilities[] | "\(.id | clean) \(.severity | clean)"] | join(", "))"
    else error("not the shape of brew vulns --json")
    end' 2>/dev/null
}

# Homebrew 7's own scanner over every installed formula, dependencies
# included — a vulnerable openssl is the same risk whoever pulled it in. Casks
# are not covered by it. Its exit code is not used: it has not been consistent
# across runs and 7.0.x versions, so the JSON decides. Its stderr is shown,
# because that is where it says when it could not tell what is installed.
#
# Returns 0 clean, 1 found or unreadable, 3 skipped. main calls it in a
# condition, where set -e does not reach inside, so every step that can fail
# is checked by hand.
check_brew() {
  command -v brew >/dev/null || { echo "homebrew: not installed, skipped"; return 3; }
  brew vulns --help >/dev/null 2>&1 || { echo "homebrew: no 'brew vulns' (needs Homebrew 7), skipped"; return 3; }
  command -v jq >/dev/null || { echo "homebrew: needs jq to read 'brew vulns', not checked"; return 1; }
  local json lines line err
  err=$(mktemp) || return 1
  json=$(brew vulns --severity "$severity" --json 2>"$err" || true)
  while IFS= read -r line; do echo "homebrew: brew says: $line"; done <"$err"
  rm -f "$err"
  if ! lines=$(brew_findings <<<"$json"); then
    echo "homebrew: could not read what 'brew vulns' answered — not checked"
    return 1
  fi
  if [ -z "$lines" ]; then
    echo "homebrew: nothing at $severity or above"
    return 0
  fi
  echo "homebrew: vulnerable formulae — 'brew upgrade' first, then look again:"
  while IFS= read -r line; do echo "  $line"; done <<<"$lines"
  return 1
}

main() {
  # Any case brew accepts, matched without tr, which a bare PATH may not have.
  case $severity in
    [lL][oO][wW] | [mM][eE][dD][iI][uU][mM] | [hH][iI][gG][hH] | [cC][rR][iI][tT][iI][cC][aA][lL]) ;;
    *) echo "SEVERITY must be low, medium, high or critical, not '$severity'" >&2; exit 2 ;;
  esac
  local failed=0 checked=0 rc
  rc=0; check_brew || rc=$?
  case $rc in 0) checked=$((checked + 1)) ;; 3) ;; *) checked=$((checked + 1)); failed=1 ;; esac
  if [ "$checked" -eq 0 ]; then
    echo "no source of installed software could be checked on this machine"
    return 1
  fi
  return "$failed"
}

case ${1:-} in
  brew-findings) brew_findings ;;
  '') main ;;
  *) sed -n '2,5p' "$0" >&2; exit 2 ;;
esac
