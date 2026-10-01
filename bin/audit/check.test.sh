#!/usr/bin/env bash
# The decision check.sh makes, against a fake `brew` on PATH: a finding fails,
# a clean answer passes, and anything it cannot read fails too — never a pass.
# Plus how a finding is printed. No Homebrew needed.
set -euo pipefail
check=$(cd "$(dirname "$0")" && pwd)/check.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL  $*" >&2; exit 1; }

# A brew whose `vulns --help` succeeds and whose scan prints $tmp/answer, its
# stderr $tmp/warning, and exits with $tmp/rc — so its exit code can lie.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/brew" <<EOF
#!/usr/bin/env bash
if [ "\${2:-}" = --help ]; then [ -e "$tmp/old" ] && exit 1; exit 0; fi
if [ "\$1" = outdated ]; then cat "$tmp/outdated"; exit 0; fi
echo "\$*" >"$tmp/args"
cat "$tmp/answer"; cat "$tmp/warning" >&2; exit "\$(cat "$tmp/rc")"
EOF
chmod +x "$tmp/bin/brew"
jq=$(command -v jq)
ln -s "$jq" "$tmp/bin/jq"

# run <rc brew exits with> <answer>; sets out and code
run() {
  echo "$1" >"$tmp/rc"; printf '%s' "$2" >"$tmp/answer"
  code=0; out=$(PATH="$tmp/bin:/usr/bin:/bin" "$check" 2>&1) || code=$?
}
expect() { [ "$code" = "$1" ] || fail "$2: exit $code, want $1 — $out"; }
: >"$tmp/warning"
: >"$tmp/outdated"

finding='{"findings": [
  {"formula": "rclone", "version": "1.75.0", "vulnerabilities": [
    {"id": "CVE-2026-88016", "severity": "HIGH"},
    {"id": "CVE-2026-88018", "severity": "CRITICAL"}]},
  {"formula": "cairo", "version": "1.18.4", "vulnerabilities": [
    {"id": "CVE-2026-1", "severity": "HIGH"}]}],
 "skipped_formulae": ["stow"]}'

run 0 "$finding";  expect 1 "a finding fails, whatever brew exits with"
grep -qF '  rclone 1.75.0: CVE-2026-88016 HIGH, CVE-2026-88018 CRITICAL' <<<"$out" || fail "finding printed: $out"
grep -qF '  cairo 1.18.4: CVE-2026-1 HIGH' <<<"$out" || fail "second formula printed: $out"
run 1 '{"findings": [], "skipped_formulae": []}'; expect 0 "a clean answer passes, whatever brew exits with"

# Everything brew might print when it could not look. Each one must fail.
for answer in '' '   ' 'Error: rate limited' '<html>502</html>' '{"error": "OSV unreachable"}' \
  '{"findings": null}' '{"results": []}' '[]' '{"findings": [{"formula": "a", "version": "1", "vulnerabilities": null}]}' \
  '{"findings": [' '{"findings": []}{"findings": []}'; do
  run 0 "$answer"; expect 1 "unreadable answer '$answer'"
done

echo 'Warning: could not tell what rsync installed' >"$tmp/warning"
run 0 '{"findings": []}'; expect 0 "a warning alone does not fail"
grep -qF 'brew says: Warning: could not tell' <<<"$out" || fail "brew's stderr shown: $out"
: >"$tmp/warning"

# A terminal escape in remote data is printed as text, not sent to the terminal.
run 0 '{"findings": [{"formula": "x", "version": "1", "vulnerabilities": [{"id": "CVE\u001b]0;pwned\u0007", "severity": "HIGH"}]}]}'
expect 1 "escape finding"
grep -qF 'CVE?]0;pwned? HIGH' <<<"$out" || fail "control characters replaced: $out"

code=0; SEVERITY=-h "$check" >/dev/null 2>&1 || code=$?; [ "$code" = 2 ] || fail "SEVERITY=-h is usage, exit $code"
code=0; out=$(PATH=/usr/bin:/bin "$check" 2>&1) || code=$?
[ "$code" = 1 ] || fail "nothing checked must not pass, exit $code — $out"

# The severity reaches brew as one argument, in any case the user typed it.
for sev in low medium high critical HIGH Critical; do
  echo 0 >"$tmp/rc"; printf '%s' '{"findings": []}' >"$tmp/answer"
  code=0; SEVERITY=$sev PATH="$tmp/bin:/usr/bin:/bin" "$check" >/dev/null 2>&1 || code=$?
  [ "$code" = 0 ] || fail "SEVERITY=$sev accepted, exit $code"
  [ "$(cat "$tmp/args")" = "vulns --severity $sev --json" ] || fail "SEVERITY=$sev passed as: $(cat "$tmp/args")"
done
echo 0 >"$tmp/rc"; code=0; PATH="$tmp/bin:/usr/bin:/bin" "$check" >/dev/null 2>&1 || code=$?
[ "$(cat "$tmp/args")" = "vulns --severity high --json" ] || fail "default severity: $(cat "$tmp/args")"
for sev in bogus '--json' 'critical; rm -rf x' 'high low' '*' -h; do
  code=0; SEVERITY=$sev PATH="$tmp/bin:/usr/bin:/bin" "$check" >/dev/null 2>&1 || code=$?
  [ "$code" = 2 ] || fail "SEVERITY='$sev' is usage, exit $code"
done

# A Homebrew without `brew vulns` is skipped, and then nothing was checked.
touch "$tmp/old"; run 0 '{"findings": []}'; rm "$tmp/old"
expect 1 "Homebrew older than 7"
grep -qF "no 'brew vulns'" <<<"$out" || fail "old Homebrew named: $out"

# brew without jq cannot be read, so it is not a pass.
mkdir -p "$tmp/nojq"; ln -sf "$tmp/bin/brew" "$tmp/nojq/brew"
code=0; out=$(PATH="$tmp/nojq:/bin" "$check" 2>&1) || code=$?
if ! PATH=/bin command -v jq >/dev/null; then
  [ "$code" = 1 ] || fail "no jq must not pass, exit $code — $out"
  grep -qF "needs jq" <<<"$out" || fail "missing jq named: $out"
fi

# The formatting on its own: exactly one line per formula, nothing when clean.
got=$("$check" brew-findings <<<"$finding")
want='rclone 1.75.0: CVE-2026-88016 HIGH, CVE-2026-88018 CRITICAL
cairo 1.18.4: CVE-2026-1 HIGH'
[ "$got" = "$want" ] || fail "brew-findings: got
$got"
got=$("$check" brew-findings <<<'{"findings": []}') || fail "brew-findings on a clean answer exits 0"
[ -z "$got" ] || fail "brew-findings on a clean answer prints nothing, got $got"
! "$check" brew-findings <<<'{"findings": null}' >/dev/null 2>&1 || fail "brew-findings refuses a wrong shape"

# Whether brew can fix it, from `brew outdated`: newer, pinned, or nothing newer.
printf '%s' '{"formulae": [
  {"name": "rclone", "installed_versions": ["1.75.0"], "current_version": "1.75.1", "pinned": false},
  {"name": "cairo", "installed_versions": ["1.18.4"], "current_version": "1.18.6", "pinned": true}],
 "casks": []}' >"$tmp/outdated"
three='{"findings": [
  {"formula": "rclone", "version": "1.75.0", "vulnerabilities": [{"id": "CVE-1", "severity": "HIGH"}]},
  {"formula": "cairo", "version": "1.18.4", "vulnerabilities": [{"id": "CVE-2", "severity": "HIGH"}]},
  {"formula": "openjpeg", "version": "2.5.4", "vulnerabilities": [{"id": "OSV-3", "severity": "HIGH"}]}]}'
run 0 "$three"; expect 1 "findings with fixes known"
grep -qF '  rclone 1.75.0 → brew upgrade to 1.75.1: CVE-1 HIGH' <<<"$out" || fail "upgrade hint: $out"
grep -qF '  cairo 1.18.4 — pinned, brew holds back 1.18.6: CVE-2 HIGH' <<<"$out" || fail "pinned hint: $out"
grep -qF '  openjpeg 2.5.4 — newest in Homebrew, no fix there yet: OSV-3 HIGH' <<<"$out" || fail "no-fix hint: $out"
grep -qF 'patch or replace it outside brew' <<<"$out" || fail "what to do with no fix: $out"

# Without an answer from `brew outdated` there is no hint — and the same verdict.
for broken in '' 'Error: offline' '{"formulae": null}' '[]' '{"casks": []}'; do
  printf '%s' "$broken" >"$tmp/outdated"
  run 0 "$three"; expect 1 "outdated answer '$broken'"
  grep -qF '  openjpeg 2.5.4: OSV-3 HIGH' <<<"$out" || fail "no hint without outdated '$broken': $out"
  grep -qF '  rclone 1.75.0: CVE-1 HIGH' <<<"$out" || fail "no hint invented from outdated '$broken': $out"
done
: >"$tmp/outdated"

# The same through the subcommand, with the file given.
printf '%s' '{"formulae": [{"name": "rclone", "current_version": "1.75.1", "pinned": false}]}' >"$tmp/o.json"
got=$("$check" brew-findings "$tmp/o.json" <<<'{"findings": [{"formula": "rclone", "version": "1.75.0", "vulnerabilities": [{"id": "CVE-1", "severity": "HIGH"}]}]}')
[ "$got" = 'rclone 1.75.0 → brew upgrade to 1.75.1: CVE-1 HIGH' ] || fail "brew-findings with outdated: $got"

for arg in --help -h bogus; do
  code=0; "$check" "$arg" >/dev/null 2>&1 || code=$?
  [ "$code" = 2 ] || fail "argument '$arg' is usage, exit $code"
done

echo "ok    audit check.sh"
