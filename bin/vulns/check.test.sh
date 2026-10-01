#!/usr/bin/env bash
# How `brew vulns --json` is read: one line per formula, every finding on it,
# nothing when there are none. No Homebrew needed.
set -euo pipefail
check=$(cd "$(dirname "$0")" && pwd)/check.sh
fail() { echo "FAIL  $*" >&2; exit 1; }

got=$("$check" brew-findings <<'EOF'
{"findings": [
  {"formula": "rclone", "version": "1.75.0", "vulnerabilities": [
    {"id": "CVE-2026-88016", "severity": "HIGH"},
    {"id": "CVE-2026-88018", "severity": "CRITICAL"}]},
  {"formula": "cairo", "version": "1.18.4", "vulnerabilities": [
    {"id": "CVE-2026-1", "severity": "HIGH"}]}],
 "skipped_formulae": ["stow"]}
EOF
)
want='rclone 1.75.0: CVE-2026-88016 HIGH, CVE-2026-88018 CRITICAL
cairo 1.18.4: CVE-2026-1 HIGH'
[ "$got" = "$want" ] || fail "findings: got
$got"

got=$("$check" brew-findings <<<'{"findings": [], "skipped_formulae": []}')
[ -z "$got" ] || fail "no findings prints nothing, got $got"

echo "ok    vulns check.sh"
