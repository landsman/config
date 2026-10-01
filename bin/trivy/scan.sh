#!/usr/bin/env bash
# Runs trivy from the mirrored image (bin/mirror/image.sh), from the root of the
# repository being scanned — what the shared dockerfile and dependencies
# workflows call instead of aquasecurity/trivy-action.
#
#   scan.sh [--docker] <Dockerfile> <trivy arguments...>
#
# <Dockerfile> is bin/trivy/Dockerfile, which pins the version. --docker hands
# trivy the host's Docker socket, for scanning an image built on this runner;
# every other scan reads files or a registry and gets no socket.
#
# The repository is mounted at /src, the working directory, so paths in the
# arguments are relative to its root. Every TRIVY_* variable in the environment
# is passed in. The vulnerability database is kept in SCAN_CACHE (default
# ~/.cache/trivy) between runs, so a workflow can cache that directory.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)

socket=()
if [ "${1:-}" = --docker ]; then socket=(-v /var/run/docker.sock:/var/run/docker.sock); shift; fi
dockerfile=${1:?usage: scan.sh [--docker] <Dockerfile> <trivy arguments...>}
shift

cache=${SCAN_CACHE:-$HOME/.cache/trivy}
mkdir -p "$cache"

env=()
while IFS= read -r name; do env+=(-e "$name"); done < <(compgen -e | grep '^TRIVY_' || true)

image=$("$here/../mirror/image.sh" pull trivy "$dockerfile")
docker run --rm -v "$PWD:/src" -w /src -v "$cache:/root/.cache/trivy" \
  ${socket[@]+"${socket[@]}"} ${env[@]+"${env[@]}"} "$image" "$@"
