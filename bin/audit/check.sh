#!/usr/bin/env bash
# Known vulnerabilities in what is installed on this machine — `make audit`.
#
#   check.sh                  every source, at or above SEVERITY (default high)
#   check.sh brew-findings [outdated.json]
#                             read `brew vulns --json` on stdin, one line per formula;
#                             with `brew outdated --json=v2`, say whether brew can fix it
#
# Exit 0: every source was checked and found nothing. Exit 1: a finding, a
# source whose answer could not be read or that said it was incomplete, or no
# source checked at all. Exit 2: usage — an unknown argument or a SEVERITY that
# is not low, medium, high or critical. It fails closed: an answer that is not
# exactly the expected shape is a failure, never a pass, because a check that
# passes when it could not look is worse than none.
#
# One function per source of installed software; a source whose tool is not on
# this machine is skipped and says so. Adding one is a function and a line in
# main. A repo's lockfiles are not here — the shared dependencies workflow
# reads those in CI. This is what a laptop actually runs.
set -euo pipefail

severity=${SEVERITY:-high}

# One scratch directory per run, removed however the run ends.
work=
cleanup() { [ -z "$work" ] || rm -rf "$work"; }
trap cleanup EXIT
trap 'exit 130' INT TERM

# Printed text that came from somewhere else — advisory ids from OSV, formula
# names from taps, brew's own error messages quoting both — has every control
# character and every invisible or direction-changing one replaced with '?':
# C0, DEL, C1 (an 8-bit CSI is an escape too), zero-width characters, the bidi
# embeddings and isolates, and the byte-order mark. A terminal escape in one
# could rewrite the lines around it; a direction override could make a finding
# read as something else.
clean_def='def clean: tostring | explode | map(
  if . < 32 or (. >= 127 and . <= 159) or (. >= 8203 and . <= 8207)
     or (. >= 8234 and . <= 8238) or (. >= 8294 and . <= 8297) or . == 65279
  then 63 else . end) | implode;'

# The shape is checked before anything is printed: a renamed key, an error
# object or a null list is a failure, not "nothing found". Slurped, so the
# answer has to be exactly one JSON document: nothing at all, two of them or
# half of one is a failure too.
#
# brew is asked for everything and the severity is filtered here, because its
# own --severity drops every vulnerability with no score — and the newest CVEs
# are the ones not scored yet. Those are always reported, as UNSCORED. A
# formula listed only with patched advisories (no open vulnerability) is not
# a finding.
#
# The optional second file is `brew outdated --json=v2`, and it only adds a
# hint: whether Homebrew already has a newer version (`brew upgrade` is the
# fix, then look again), holds one back with a pin, or has nothing newer — no
# fix in Homebrew yet, so it waits for one or gets patched outside brew. An
# entry it cannot use is ignored, a missing or unreadable file means no hint,
# and neither ever changes the verdict.
brew_findings() {
  local outdated=${1:-/dev/null}
  jq -e . "$outdated" >/dev/null 2>&1 || outdated=/dev/null
  jq -r -s --slurpfile o "$outdated" --arg sev "$severity" "$clean_def"'
    def rank: ({"low": 1, "medium": 2, "moderate": 2, "high": 3, "critical": 4})[tostring | ascii_downcase] // 0;
    ($sev | rank) as $floor
    | (($o[0] | type) == "object" and ($o[0].formulae | type) == "array") as $known
    | ($o[0] | if $known then .formulae else [] end
        | map(select(type == "object" and (.name | type) == "string" and (.current_version | type) == "string")
              | {key: (.name | split("/") | last), value: .})
        | from_entries) as $newer
    | def fix: $newer[.formula | tostring] as $n
        | if $n == null then (if $known then " — newest in Homebrew, no fix there yet" else "" end)
          elif $n.pinned == true then " — pinned, brew holds back \($n.current_version | clean)"
          else " → brew upgrade to \($n.current_version | clean)"
          end;
    if length == 1 and (.[0] | type) == "object" and (.[0].findings | type) == "array"
       and all(.[0].findings[]; type == "object" and (.vulnerabilities | type) == "array")
    then .[0].findings[]
      | [.vulnerabilities[] | (.severity | rank) as $r | select($r == 0 or $r >= $floor)
          | "\(.id | clean) \(if $r == 0 then "UNSCORED" else (.severity | clean) end)"] as $open
      | select($open | length > 0)
      | "\(.formula | clean) \(.version | clean)\(fix): \($open | join(", "))"
    else error("not the shape of brew vulns --json")
    end' 2>/dev/null
}

# What the same answer says about its own completeness, once its shape is known
# to be right: how many formulae have an open vulnerability at any severity, and
# which formulae brew skipped because it cannot trace their source.
brew_open_count() { jq -r '[.findings[] | select(.vulnerabilities | length > 0)] | length'; }
brew_skipped() {
  jq -r "$clean_def"'.skipped_formulae // [] | if type == "array" then .[] | clean else empty end'
}

# Homebrew 7's own scanner over every installed formula it can trace to a
# source, dependencies included — a vulnerable openssl is the same risk
# whoever pulled it in. Casks are not covered by it, and the formulae it
# cannot trace are listed as not checked. Its stderr is shown, cleaned, because
# that is where it says when it could not tell what is installed. Its exit code
# counts only when it found nothing: then a failing one means it is telling us
# its answer is incomplete.
#
# Returns 0 clean, 1 found or unreadable or incomplete, 3 skipped. main calls it
# in a condition, where set -e does not reach inside, so every step that can
# fail is checked by hand.
check_brew() {
  command -v brew >/dev/null || { echo "homebrew: not installed, skipped"; return 3; }
  brew vulns --help >/dev/null 2>&1 || { echo "homebrew: no 'brew vulns' (needs Homebrew 7), skipped"; return 3; }
  command -v jq >/dev/null || { echo "homebrew: needs jq to read 'brew vulns', not checked"; return 1; }
  local json lines line rc=0 skipped
  json=$(brew vulns --json 2>"$work/err") || rc=$?
  jq -R -r "$clean_def"'clean | "homebrew: brew says: \(.)"' <"$work/err" || true
  brew outdated --json=v2 --formula >"$work/outdated" 2>/dev/null || true

  if ! lines=$(brew_findings "$work/outdated" <<<"$json"); then
    echo "homebrew: could not read what 'brew vulns' answered — not checked"
    return 1
  fi
  skipped=$(brew_skipped <<<"$json" | paste -sd ' ' - || true)
  [ -z "$skipped" ] || echo "homebrew: not checked, no source brew can trace ($(wc -w <<<"$skipped" | tr -d ' ')): $skipped"

  if [ -n "$lines" ]; then
    echo "homebrew: vulnerable formulae:"
    while IFS= read -r line; do echo "  $line"; done <<<"$lines"
    echo "homebrew: 'brew upgrade' the ones it can, then run this again. A formula that is"
    echo "  newest in Homebrew has no fix there yet: wait for one, or patch or replace it outside brew."
    return 1
  fi
  if [ "$rc" != 0 ] && [ "$(brew_open_count <<<"$json")" = 0 ]; then
    echo "homebrew: 'brew vulns' found nothing but exited $rc — it says its answer is incomplete (see above), not checked"
    return 1
  fi
  echo "homebrew: nothing at $severity or above"
  return 0
}

main() {
  # Any case brew accepts, matched without tr, which a bare PATH may not have.
  case $severity in
    [lL][oO][wW] | [mM][eE][dD][iI][uU][mM] | [hH][iI][gG][hH] | [cC][rR][iI][tT][iI][cC][aA][lL]) ;;
    *) echo "SEVERITY must be low, medium, high or critical, not '$severity'" >&2; exit 2 ;;
  esac
  work=$(mktemp -d) || { echo "could not create a scratch directory" >&2; exit 1; }
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
  brew-findings) brew_findings "${2:-}" ;;
  '') main ;;
  *) sed -n '2,7p' "$0" >&2; exit 2 ;;
esac
