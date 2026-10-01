#!/usr/bin/env bash
# Known vulnerabilities in what is installed on this machine — `make vulns`.
#
#   check.sh                    every source, at or above SEVERITY (default high)
#   check.sh brew-findings      format `brew vulns --json` from stdin, one line per formula
#
# One function per source of installed software. A source whose tool is not on
# this machine is skipped and says so, so the same command runs on macOS, Linux
# and a machine with half of it. Adding a source is a function and a line in
# main. Exits 1 when any source found something, 0 when none did.
#
# A repo's lockfiles are not here: the shared dependencies workflow in CI reads
# those. This is the other half — what a laptop actually runs.
set -euo pipefail

severity=${SEVERITY:-high}

brew_findings() {
  jq -r '.findings[] | "\(.formula) \(.version): \([.vulnerabilities[] | "\(.id) \(.severity)"] | join(", "))"'
}

# Homebrew 7's own scanner, against every installed formula — dependencies
# included, since a vulnerable openssl is the same risk whoever pulled it in.
# Casks are not covered by it. Its exit code says nothing reliable (0 with
# findings under --json, 1 with none without it), so the JSON decides.
check_brew() {
  command -v brew >/dev/null || { echo "homebrew: not installed, skipped"; return 0; }
  brew vulns --help >/dev/null 2>&1 || { echo "homebrew: no 'brew vulns' (needs Homebrew 7), skipped"; return 0; }
  local json lines line
  json=$(brew vulns --severity "$severity" --json 2>/dev/null || true)
  [ -n "$json" ] || { echo "homebrew: 'brew vulns' printed nothing, check it by hand"; return 1; }
  lines=$(brew_findings <<<"$json")
  if [ -z "$lines" ]; then
    echo "homebrew: nothing at $severity or above"
    return 0
  fi
  echo "homebrew: vulnerable formulae — 'brew upgrade' first, then look again:"
  while IFS= read -r line; do echo "  $line"; done <<<"$lines"
  return 1
}

main() {
  command -v jq >/dev/null || { echo "needs jq" >&2; exit 2; }
  local found=0
  check_brew || found=1
  return "$found"
}

case ${1:-} in
  brew-findings) brew_findings ;;
  '') main ;;
  *) sed -n '2,5p' "$0" >&2; exit 2 ;;
esac
