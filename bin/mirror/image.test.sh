#!/usr/bin/env bash
# What image.sh reads off a FROM line, and what it refuses. No Docker, no network.
set -euo pipefail
image=$(cd "$(dirname "$0")" && pwd)/image.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL  $*" >&2; exit 1; }
d=$tmp/Dockerfile

printf '# comment\nFROM aquasec/trivy:0.74.0@sha256:62b1e6 AS base\nLABEL a=b\nFROM other:1@sha256:00\n' >"$d"
[ "$("$image" ref "$d")" = aquasec/trivy:0.74.0@sha256:62b1e6 ] || fail "ref is the first FROM, without AS"
[ "$("$image" tag "$d")" = 0.74.0 ] || fail "tag drops the digest"

printf 'FROM ghcr.io/x/y:1.2.3@sha256:ab\n' >"$d"
[ "$("$image" tag "$d")" = 1.2.3 ] || fail "a registry with no port"

printf 'FROM localhost:5000/y:1.2.3@sha256:ab\n' >"$d"
[ "$("$image" tag "$d")" = 1.2.3 ] || fail "a registry with a port is not the tag"

# A tag without a digest is what the mirror is meant to stop running.
printf 'FROM semgrep/semgrep:1.177.0\n' >"$d"
! "$image" ref "$d" 2>/dev/null || fail "a FROM with no digest is refused"
printf 'FROM semgrep/semgrep@sha256:ab\n' >"$d"
! "$image" tag "$d" 2>/dev/null || fail "a FROM with no tag is refused"

echo "ok    mirror image.sh"
