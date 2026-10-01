#!/usr/bin/env bash
# Known vulnerabilities in what is installed on this machine — `make audit`.
#
#   check.sh                  every source, at or above SEVERITY (default high)
#   check.sh brew-findings [outdated.json]
#                             read `brew vulns --json` on stdin, print its findings;
#                             with `brew outdated --json=v2`, say whether brew can fix them
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
#
# Colour only on a terminal, and never with NO_COLOR set (no-color.org);
# FORCE_COLOR turns it on anywhere. Piped or logged, the output is plain text.
set -euo pipefail

severity=${SEVERITY:-high}

# One scratch directory per run, removed however the run ends.
work=
cleanup() { [ -z "$work" ] || rm -rf "$work"; }
trap cleanup EXIT
trap 'exit 130' INT TERM

if [ -n "${FORCE_COLOR:-}" ] || { [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; }; then
  bold=$'\e[1m' dim=$'\e[2m' red=$'\e[31m' green=$'\e[32m' yellow=$'\e[33m' magenta=$'\e[35m' off=$'\e[0m'
else
  bold='' dim='' red='' green='' yellow='' magenta='' off=''
fi

# Printed text that came from somewhere else — advisory ids from OSV, formula
# names from taps, brew's own error messages quoting both — has every control
# character and every invisible or direction-changing one replaced with '?':
# C0, DEL, C1 (an 8-bit CSI is an escape too), zero-width characters, the bidi
# embeddings and isolates, and the byte-order mark. A terminal escape in one
# could rewrite the lines around it; a direction override could make a finding
# read as something else. That also keeps tabs out, which the records below
# are separated by.
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
#
# Output is records, one per line, tab-separated, for render_brew to lay out:
#   F <formula> <version> <upgrade|pinned|none|unknown> <newer version>
#   V <id> <severity>         one per open vulnerability of the F above it
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
        | if $n == null then (if $known then ["none", ""] else ["unknown", ""] end)
          elif $n.pinned == true then ["pinned", ($n.current_version | clean)]
          else ["upgrade", ($n.current_version | clean)]
          end;
    if length == 1 and (.[0] | type) == "object" and (.[0].findings | type) == "array"
       and all(.[0].findings[]; type == "object" and (.vulnerabilities | type) == "array")
    then .[0].findings[]
      | [.vulnerabilities[] | (.severity | rank) as $r | select($r == 0 or $r >= $floor)
          | ["V", (.id | clean), (if $r == 0 then "UNSCORED" else (.severity | clean | ascii_upcase) end)]] as $open
      | select($open | length > 0)
      | (["F", (.formula | clean), (.version | clean)] + fix), $open[]
      | join("\t")
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

sev_colour() {
  case $1 in
    CRITICAL) printf '%s' "$bold$red" ;;
    HIGH) printf '%s' "$red" ;;
    MEDIUM) printf '%s' "$yellow" ;;
    UNSCORED) printf '%s' "$magenta" ;;
    *) printf '%s' "$dim" ;;
  esac
}

# The records from brew_findings, laid out: each formula on a line of its own
# with what fixes it, its vulnerabilities under it with the severity aligned.
render_brew() {
  local records=$1 kind name ver fix newer id sev width=0 head n=0
  while IFS=$'\t' read -r kind name ver _; do
    [ "$kind" = F ] || continue
    n=$((n + 1)); head="$name $ver"; [ ${#head} -le "$width" ] || width=${#head}
  done <<<"$records"
  echo "  ${bold}vulnerable ($n)${off}"
  while IFS=$'\t' read -r kind name ver fix newer; do
    if [ "$kind" = F ]; then
      case $fix in
        upgrade) fix="${green}brew upgrade → $newer${off}" ;;
        pinned) fix="${yellow}pinned — brew holds back $newer${off}" ;;
        none) fix="${yellow}no fix in Homebrew yet${off}" ;;
        *) fix="" ;;
      esac
      printf "    ${bold}%-${width}s${off}  %s\n" "$name $ver" "$fix"
    else
      id=$name sev=$ver
      printf '      %-20s %s%s%s\n' "$id" "$(sev_colour "$sev")" "$sev" "$off"
    fi
  done <<<"$records"
}

# The formulae brew skipped, last and dimmed: worth knowing, not the news.
show_skipped() {
  [ -n "$1" ] || return 0
  echo "  ${dim}not checked ($(wc -w <<<"$1" | tr -d ' ')) — brew cannot trace their source:${off}"
  fold -s -w 72 <<<"$1" | sed "s/^/    $dim/;s/ *\$/$off/"
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
  echo "${bold}homebrew${off}"
  command -v brew >/dev/null || { echo "  ${dim}not installed — skipped${off}"; return 3; }
  brew vulns --help >/dev/null 2>&1 || { echo "  ${dim}no 'brew vulns' (needs Homebrew 7) — skipped${off}"; return 3; }
  command -v jq >/dev/null || { echo "  ${red}✗ needs jq to read 'brew vulns' — not checked${off}"; return 1; }
  local json records rc=0 skipped
  json=$(brew vulns --json 2>"$work/err") || rc=$?
  jq -R -r "$clean_def"'clean | "  brew says: \(.)"' <"$work/err" | sed "s/^/$dim/;s/\$/$off/" || true
  brew outdated --json=v2 --formula >"$work/outdated" 2>/dev/null || true

  if ! records=$(brew_findings "$work/outdated" <<<"$json"); then
    echo "  ${red}✗ could not read what 'brew vulns' answered — not checked${off}"
    return 1
  fi
  skipped=$(brew_skipped <<<"$json" | paste -sd ' ' - || true)

  if [ -n "$records" ]; then
    render_brew "$records"
    show_skipped "$skipped"
    echo "  ${bold}next${off}"
    grep -q $'\tupgrade\t' <<<"$records" && echo "    'brew upgrade', then run this again"
    grep -q $'\tpinned\t' <<<"$records" && echo "    'brew unpin' what is pinned, or accept the risk"
    grep -q $'\tnone\t' <<<"$records" && echo "    no fix in Homebrew yet: wait for one, or patch or replace it outside brew"
    echo "  ${red}✗ vulnerable formulae at $severity or above${off}"
    return 1
  fi
  show_skipped "$skipped"
  if [ "$rc" != 0 ] && [ "$(brew_open_count <<<"$json")" = 0 ]; then
    echo "  ${red}✗ 'brew vulns' found nothing but exited $rc — it says its answer is incomplete (see above), not checked${off}"
    return 1
  fi
  echo "  ${green}✓ nothing at $severity or above${off}"
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
    echo "${red}✗ no source of installed software could be checked on this machine${off}"
    return 1
  fi
  return "$failed"
}

case ${1:-} in
  brew-findings) brew_findings "${2:-}" ;;
  '') main ;;
  *) sed -n '2,7p' "$0" >&2; exit 2 ;;
esac
