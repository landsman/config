#!/usr/bin/env bash
# The decision check.sh makes, against a fake `brew` on PATH: a finding fails,
# a clean and complete answer passes, and anything it cannot read — or that
# brew itself calls incomplete — fails too, never a pass. Plus how findings are
# filtered and printed. No Homebrew needed; the data is made up.
set -euo pipefail
check=$(cd "$(dirname "$0")" && pwd)/check.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL  $*" >&2; exit 1; }

# A brew whose `vulns --help` succeeds (unless $tmp/old exists), whose scan
# prints $tmp/answer and $tmp/warning on stderr and exits with $tmp/rc, and
# whose `outdated` prints $tmp/outdated. It records the scan's arguments.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/brew" <<EOF
#!/usr/bin/env bash
if [ "\${2:-}" = --help ]; then [ -e "$tmp/old" ] && exit 1; exit 0; fi
if [ "\$1" = outdated ]; then cat "$tmp/outdated"; exit 0; fi
echo "\$*" >"$tmp/args"
cat "$tmp/answer"; cat "$tmp/warning" >&2; exit "\$(cat "$tmp/rc")"
EOF
chmod +x "$tmp/bin/brew"
ln -s "$(command -v jq)" "$tmp/bin/jq"
: >"$tmp/warning"
: >"$tmp/outdated"

# run <rc brew exits with> <answer>; sets out and code. SEVERITY passes through.
run() {
  echo "$1" >"$tmp/rc"; printf '%s' "$2" >"$tmp/answer"
  code=0; out=$(PATH="$tmp/bin:/usr/bin:/bin" "$check" 2>&1) || code=$?
}
expect() { [ "$code" = "$1" ] || fail "$2: exit $code, want $1 — $out"; }
has() { grep -qF -- "$1" <<<"$out" || fail "$2: no '$1' in: $out"; }
hasnt() { ! grep -qF -- "$1" <<<"$out" || fail "$2: '$1' in: $out"; }
# formula <name version> <hint, or '' for none>: its line, with that hint after it
formula() {
  local line trimmed
  line=$(grep -F -- "    $1 " <<<"$out" | grep -v '^      ' | head -1 || true)
  [ -n "$line" ] || fail "$3: no formula line '$1' in: $out"
  if [ -n "$2" ]; then
    grep -qF -- "$2" <<<"$line" || fail "$3: '$1' without '$2': $line"
  else
    trimmed=${line#"${line%%[! ]*}"}; trimmed=${trimmed%"${trimmed##*[! ]}"}
    [ "$trimmed" = "$1" ] || fail "$3: '$1' has a hint: $line"
  fi
}
# vuln <id> <severity>: its line under a formula, severity in the column after it
vuln() { grep -qE -- "^      $(printf '%s' "$1" | sed 's/[][\.*^$?+(){}|/]/\\&/g') +$2\$" <<<"$out" || fail "$3: no '$1 $2' line in: $out"; }

finding='{"findings": [
  {"formula": "libfoo", "version": "1.0.0", "vulnerabilities": [
    {"id": "CVE-0000-0001", "severity": "HIGH"},
    {"id": "CVE-0000-0002", "severity": "CRITICAL"}]},
  {"formula": "libbar", "version": "2.0.0", "vulnerabilities": [
    {"id": "CVE-0000-0003", "severity": "HIGH"}]}],
 "skipped_formulae": []}'
clean='{"findings": [], "skipped_formulae": []}'

# --- the verdict -----------------------------------------------------------

run 1 "$finding"; expect 1 "a finding fails"
formula 'libfoo 1.0.0' '' "first formula printed"
vuln CVE-0000-0001 HIGH "its first vulnerability"; vuln CVE-0000-0002 CRITICAL "its second"
formula 'libbar 2.0.0' '' "second formula printed"; vuln CVE-0000-0003 HIGH "and its vulnerability"
has 'vulnerable (2)' "formulae counted"; has '✗ vulnerable formulae at high or above' "verdict line"
run 0 "$finding"; expect 1 "a finding fails even when brew exits 0"
run 0 "$clean"; expect 0 "a clean, complete answer passes"
has 'nothing at high or above' "clean answer says so"

# brew found nothing yet exits non-zero: it is saying the answer is incomplete
# (an untrusted tap not scanned, an install it could not identify).
echo 'Warning: 2 installed kegs from an untrusted tap not scanned' >"$tmp/warning"
run 1 "$clean"; expect 1 "nothing found but brew failed — incomplete"
has 'it says its answer is incomplete' "incomplete named"
has 'brew says: Warning: 2 installed kegs' "brew's warning shown"
: >"$tmp/warning"
# ...but a failing exit explained by findings below the floor is not that.
run 1 '{"findings": [{"formula": "libfoo", "version": "1", "vulnerabilities": [{"id": "CVE-0000-0009", "severity": "LOW"}]}]}'
expect 0 "a low finding under SEVERITY=high, brew exiting 1 for it"

# Everything brew might print when it could not look. Each one must fail.
for answer in '' '   ' 'Error: rate limited' '<html>502</html>' '{"error": "OSV unreachable"}' \
  '{"findings": null}' '{"findings": {}}' '{"findings": "none"}' '{"results": []}' '[]' \
  '{"findings": [1]}' '{"findings": [{"formula": "a", "version": "1", "vulnerabilities": null}]}' \
  '{"findings": [' '{"findings": []}{"findings": []}'; do
  run 0 "$answer"; expect 1 "unreadable answer '$answer'"
  has 'could not read' "unreadable named for '$answer'"
done

# --- severity --------------------------------------------------------------

# brew is asked for everything; the floor is applied here, so an unscored
# vulnerability — brew's --severity drops those at every level — is shown.
mixed='{"findings": [{"formula": "libfoo", "version": "1.0.0", "vulnerabilities": [
  {"id": "CVE-0000-0010", "severity": "LOW"}, {"id": "CVE-0000-0011", "severity": "MEDIUM"},
  {"id": "CVE-0000-0012", "severity": "HIGH"}, {"id": "CVE-0000-0013", "severity": "CRITICAL"},
  {"id": "CVE-0000-0014", "severity": "UNKNOWN"}, {"id": "CVE-0000-0015", "severity": null},
  {"id": "CVE-0000-0016"}]}]}'
run 1 "$mixed"; expect 1 "mixed severities"
[ "$(cat "$tmp/args")" = "vulns --json" ] || fail "brew asked with no --severity: $(cat "$tmp/args")"
vuln CVE-0000-0012 HIGH "high floor"; vuln CVE-0000-0013 CRITICAL "high floor"
vuln CVE-0000-0014 UNSCORED "unknown"; vuln CVE-0000-0015 UNSCORED "null"; vuln CVE-0000-0016 UNSCORED "missing"
hasnt 'CVE-0000-0010' "low under high"; hasnt 'CVE-0000-0011' "medium under high"
SEVERITY=critical run 1 "$mixed"; hasnt 'CVE-0000-0012' "high under critical"; vuln CVE-0000-0013 CRITICAL "critical at critical"
vuln CVE-0000-0014 UNSCORED "unscored at critical"
SEVERITY=low run 1 "$mixed"; vuln CVE-0000-0010 LOW "everything at low"; vuln CVE-0000-0011 MEDIUM "everything at low"
SEVERITY=Medium run 1 "$mixed"; vuln CVE-0000-0011 MEDIUM "case-insensitive floor"; hasnt 'CVE-0000-0010' "low under medium"
run 1 '{"findings": [{"formula": "libfoo", "version": "1", "vulnerabilities": [{"id": "CVE-0000-0017", "severity": "UNKNOWN"}]}]}'
expect 1 "only unscored vulnerabilities still fail"
run 1 '{"findings": [{"formula": "libfoo", "version": "1", "vulnerabilities": [{"id": "CVE-0000-0018", "severity": "high"}]}]}'
vuln CVE-0000-0018 HIGH "a severity in another case is printed in capitals"

for sev in bogus '--json' 'critical; rm -rf x' 'high low' '*' -h ''; do
  code=0; SEVERITY=$sev PATH="$tmp/bin:/usr/bin:/bin" "$check" >/dev/null 2>&1 || code=$?
  if [ -z "$sev" ]; then [ "$code" != 2 ] || fail "empty SEVERITY falls back to high"
  else [ "$code" = 2 ] || fail "SEVERITY='$sev' is usage, exit $code"; fi
done

# Patched-only: listed, but no open vulnerability — not a finding.
run 0 '{"findings": [{"formula": "libfoo", "version": "1", "vulnerabilities": [], "patched": ["CVE-0000-0020"]}]}'
expect 0 "patched-only is not a finding"; hasnt 'libfoo' "patched-only not listed"

# --- what was not checked --------------------------------------------------

run 0 '{"findings": [], "skipped_formulae": ["libbaz", "libqux"]}'
expect 0 "skipped formulae alone do not fail"
has 'not checked (2) — brew cannot trace their source:' "skipped formulae counted"
has '    libbaz libqux' "skipped formulae named"
run 0 '{"findings": [{"formula": "libfoo", "version": "1", "vulnerabilities": [{"id": "CVE-1", "severity": "HIGH"}]}], "skipped_formulae": ["libbaz"]}'
[ "$(grep -n 'not checked' <<<"$out" | cut -d: -f1)" -gt "$(grep -n 'vulnerable (1)' <<<"$out" | cut -d: -f1)" ] || fail "skipped list after the findings: $out"

# --- output integrity ------------------------------------------------------

# Remote text is printed as text: C0, DEL, C1, zero-width, bidi, BOM all become '?',
# in every field that reaches the terminal.
evil='{"findings": [{"formula": "lib\u001b[2Jfoo\u007f", "version": "1\u009b0", "vulnerabilities": [
  {"id": "CVE\u001b]0;x\u0007-​‮⁦﻿1", "severity": "HIGH"}]}]}'
printf '%s' '{"formulae": [{"name": "lib\u001b[2Jfoo\u007f", "current_version": "2‮0", "pinned": false}]}' >"$tmp/outdated"
run 0 "$evil"; expect 1 "escape finding"
formula 'lib?[2Jfoo? 1?0' 'brew upgrade → 2?0' "every control and invisible character replaced"
vuln 'CVE?]0;x?-????1' HIGH "in the id too"
printf '%s' "$out" | LC_ALL=C grep -q $'\e' && fail "an escape reached the output: $out"
: >"$tmp/outdated"
printf 'Error: Invalid JSON: unexpected \033]0;PWNED\007 and \342\200\256 here\n' >"$tmp/warning"
run 0 "$clean"; has 'brew says: Error: Invalid JSON: unexpected ?]0;PWNED? and ? here' "brew's stderr cleaned"
printf 'last line with no newline' >"$tmp/warning"
run 0 "$clean"; has 'brew says: last line with no newline' "stderr's last line kept"
: >"$tmp/warning"

# --- where brew stands on each finding -------------------------------------

printf '%s' '{"formulae": [
  {"name": "libfoo", "installed_versions": ["1.0.0"], "current_version": "1.0.1", "pinned": false},
  {"name": "libbar", "installed_versions": ["2.0.0"], "current_version": "2.0.5", "pinned": true},
  {"name": "sometap/tap/libtap", "installed_versions": ["3.0.0"], "current_version": "3.1.0", "pinned": false}],
 "casks": []}' >"$tmp/outdated"
four='{"findings": [
  {"formula": "libfoo", "version": "1.0.0", "vulnerabilities": [{"id": "CVE-1", "severity": "HIGH"}]},
  {"formula": "libbar", "version": "2.0.0", "vulnerabilities": [{"id": "CVE-2", "severity": "HIGH"}]},
  {"formula": "libtap", "version": "3.0.0", "vulnerabilities": [{"id": "CVE-4", "severity": "HIGH"}]},
  {"formula": "libnew", "version": "4.0.0", "vulnerabilities": [{"id": "OSV-3", "severity": "HIGH"}]}]}'
run 0 "$four"; expect 1 "findings with fixes known"
formula 'libfoo 1.0.0' 'brew upgrade → 1.0.1' "upgrade hint"
formula 'libbar 2.0.0' 'pinned — brew holds back 2.0.5' "pinned hint"
formula 'libtap 3.0.0' 'brew upgrade → 3.1.0' "a tap formula matched by its short name"
formula 'libnew 4.0.0' 'no fix in Homebrew yet' "no-fix hint"
has "'brew upgrade', then run this again" "next: upgrade"
has "'brew unpin' what is pinned" "next: pinned"
has 'patch or replace it outside brew' "next: no fix"
# Only the advice that applies.
printf '%s' '{"formulae": []}' >"$tmp/outdated"
run 0 '{"findings": [{"formula": "libnew", "version": "4.0.0", "vulnerabilities": [{"id": "OSV-3", "severity": "HIGH"}]}]}'
hasnt "'brew upgrade'" "no upgrade advice without an upgrade"; hasnt "'brew unpin'" "no unpin advice without a pin"
printf '%s' '{"formulae": [{"name": "libfoo", "current_version": "1.0.1", "pinned": false}]}' >"$tmp/outdated"
run 0 '{"findings": [{"formula": "libfoo", "version": "1.0.0", "vulnerabilities": [{"id": "CVE-1", "severity": "HIGH"}]}]}'
hasnt 'patch or replace it outside brew' "no outside-brew advice when brew has the fix"

# Without a usable answer from `brew outdated` there is no hint — and the same verdict.
for broken in '' 'Error: offline' '{"formulae": null}' '[]' '{"casks": []}'; do
  printf '%s' "$broken" >"$tmp/outdated"
  run 0 "$four"; expect 1 "outdated answer '$broken'"
  formula 'libnew 4.0.0' '' "no hint without outdated '$broken'"
  formula 'libfoo 1.0.0' '' "no hint invented from outdated '$broken'"
done
# Entries it cannot use are ignored, the rest still give their hint.
for junk in '1' '"x"' 'null' '{"current_version": "9"}' '{"name": "libnew"}' '{"name": 5, "current_version": "9"}'; do
  printf '{"formulae": [%s, {"name": "libfoo", "current_version": "1.0.1", "pinned": false}]}' "$junk" >"$tmp/outdated"
  run 0 "$four"; expect 1 "outdated entry $junk"
  formula 'libfoo 1.0.0' 'brew upgrade → 1.0.1' "usable entry beside $junk"
  hasnt 'could not read' "outdated entry $junk is not unreadable"
  hasnt '→ null' "no null version from $junk"
done
: >"$tmp/outdated"

# --- skipped sources and nothing checked -----------------------------------

touch "$tmp/old"; run 0 "$clean"; rm "$tmp/old"
expect 1 "Homebrew older than 7: skipped, so nothing was checked"
has "no 'brew vulns'" "old Homebrew named"; has 'no source of installed software' "nothing checked named"

code=0; out=$(PATH=/usr/bin:/bin "$check" 2>&1) || code=$?
if ! PATH=/usr/bin:/bin command -v brew >/dev/null; then
  expect 1 "no brew at all must not pass"
fi

mkdir -p "$tmp/nojq"; ln -sf "$tmp/bin/brew" "$tmp/nojq/brew"
for tool in mktemp paste; do ln -sf "$(command -v "$tool")" "$tmp/nojq/$tool"; done
code=0; out=$(PATH="$tmp/nojq:/bin" "$check" 2>&1) || code=$?
if ! PATH=/bin command -v jq >/dev/null; then
  expect 1 "no jq must not pass"; has "needs jq" "missing jq named"
fi

# No scratch files left behind, whichever way the run ended.
before=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -newer "$tmp/bin/brew" 2>/dev/null | wc -l)
run 0 "$finding"; run 0 "$clean"; run 0 'garbage'
after=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -newer "$tmp/bin/brew" 2>/dev/null | wc -l)
[ "$before" = "$after" ] || fail "scratch files left behind: $before before, $after after"

# --- the subcommand and usage ----------------------------------------------

got=$("$check" brew-findings <<<"$finding")
want=$(printf 'F\tlibfoo\t1.0.0\tunknown\t\nV\tCVE-0000-0001\tHIGH\nV\tCVE-0000-0002\tCRITICAL\nF\tlibbar\t2.0.0\tunknown\t\nV\tCVE-0000-0003\tHIGH')
[ "$got" = "$want" ] || fail "brew-findings: got
$got"
got=$("$check" brew-findings <<<"$clean") || fail "brew-findings on a clean answer exits 0"
[ -z "$got" ] || fail "brew-findings on a clean answer prints nothing, got $got"
! "$check" brew-findings <<<'{"findings": null}' >/dev/null 2>&1 || fail "brew-findings refuses a wrong shape"
printf '%s' '{"formulae": [{"name": "libfoo", "current_version": "1.0.1", "pinned": false}]}' >"$tmp/o.json"
got=$("$check" brew-findings "$tmp/o.json" <<<'{"findings": [{"formula": "libfoo", "version": "1.0.0", "vulnerabilities": [{"id": "CVE-1", "severity": "HIGH"}]}]}')
[ "$got" = "$(printf 'F	libfoo	1.0.0	upgrade	1.0.1
V	CVE-1	HIGH')" ] || fail "brew-findings with outdated: $got"

for arg in --help -h bogus; do
  code=0; "$check" "$arg" >/dev/null 2>&1 || code=$?
  [ "$code" = 2 ] || fail "argument '$arg' is usage, exit $code"
done

# --- colour -----------------------------------------------------------------

# Plain when piped (every run above), coloured only when asked for or on a terminal.
FORCE_COLOR=1 run 0 "$finding"
printf '%s' "$out" | LC_ALL=C grep -q $'\e\\[31m' || fail "FORCE_COLOR gives colour: $out"
printf '%s' "$out" | LC_ALL=C grep -q $'\e\\[1m\e\\[31mCRITICAL' || fail "critical in bold red: $out"
code=0; out=$(NO_COLOR=1 PATH="$tmp/bin:/usr/bin:/bin" "$check" 2>&1) || code=$?
printf '%s' "$out" | LC_ALL=C grep -q $'\e' && fail "NO_COLOR when piped gives none: $out"
if command -v script >/dev/null && script -q /dev/null true </dev/null >/dev/null 2>&1; then
  out=$(NO_COLOR=1 PATH="$tmp/bin:/usr/bin:/bin" script -q /dev/null "$check" </dev/null 2>&1 || true)
  printf '%s' "$out" | LC_ALL=C grep -q $'\e\\[' && fail "NO_COLOR on a terminal gives none: $out"
fi

echo "ok    audit check.sh"
