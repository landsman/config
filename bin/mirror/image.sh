#!/usr/bin/env bash
# The tool images this repo mirrors into GHCR: ghcr.io/landsman/<tool>-mirror,
# built from bin/<tool>/Dockerfile — today semgrep and trivy.
#
#   image.sh ref <Dockerfile>          the upstream image the FROM line names
#   image.sh tag <Dockerfile>          its version tag, without the digest
#   image.sh pull <tool> <Dockerfile>  pull the image to run, print its name
#   image.sh publish <tool>            build and push the mirror (CI does this)
#
# The FROM line is the one place a version lives, and the line Dependabot bumps:
# `FROM <image>:<tag>@sha256:<digest>`. The tag names the mirror's tag; the
# digest is what the build and the fallback pull, so a tag re-pointed upstream —
# trivy's were, in March 2026 — cannot change what runs here. Dependabot bumps
# tag and digest together, after the cooldown in .github/dependabot.yml.
set -euo pipefail

owner=ghcr.io/landsman

ref() {
  local r
  r=$(sed -n 's|^FROM \([^ ]*\).*|\1|p' "$1" | head -1)
  case $r in
    *:*@sha256:*) echo "$r" ;;
    *) echo "FROM in $1 is not <image>:<tag>@sha256:<digest>: $r" >&2; exit 1 ;;
  esac
}

tag() {
  local r
  r=$(ref "$1")
  r=${r%@*}
  echo "${r##*:}"
}

# The mirror first. Right after a bump the mirror lacks the new tag for a
# minute, and a package pushed for the first time is private until someone
# flips it; either way the upstream image, by digest, stands in — a slow run,
# not a red one, and still the exact image the FROM line names.
pull() {
  local tool=$1 dockerfile=$2 mirror upstream
  mirror=$owner/$tool-mirror:$(tag "$dockerfile")
  upstream=$(ref "$dockerfile")
  if docker pull -q "$mirror" >/dev/null 2>&1; then
    echo "$mirror"
  else
    echo "$mirror not pullable - using $upstream" >&2
    docker pull -q "$upstream" >/dev/null
    echo "$upstream"
  fi
}

# Relabelled, nothing added: see bin/semgrep/Dockerfile for why a build rather
# than a retag. amd64 and arm64, because a laptop is arm64 and a single-arch
# copy of a multi-arch image will not start there. Nothing runs in the build,
# so the second platform needs no emulation. --pull because the FROM is a
# digest anyway, and a stale local copy is not what was reviewed.
publish() {
  local tool=$1 dockerfile mirror
  dockerfile=bin/$tool/Dockerfile
  mirror=$owner/$tool-mirror:$(tag "$dockerfile")
  docker buildx inspect mirror >/dev/null 2>&1 || docker buildx create --name mirror --driver docker-container >/dev/null
  docker buildx build --builder mirror --pull --push \
    --platform linux/amd64,linux/arm64 \
    -t "$mirror" -f "$dockerfile" "bin/$tool"
}

case ${1:-} in
  ref | tag) "$1" "${2:?Dockerfile}" ;;
  pull) pull "${2:?tool}" "${3:?Dockerfile}" ;;
  publish) publish "${2:?tool}" ;;
  *) sed -n '2,9p' "$0" >&2; exit 2 ;;
esac
