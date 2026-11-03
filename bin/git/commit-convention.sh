#!/usr/bin/env bash
# Runs commit-convention.ts, and exists only to find bun — see forbidden-names.sh
# for why a hook cannot trust the PATH it was started with.
#
# Fail closed: no bun, no commit. Skip a repo on purpose with
#   git config hook.commit-convention.enabled false
set -euo pipefail
dir=$(cd "$(dirname "$0")" && pwd)
for bun in bun /opt/homebrew/bin/bun /home/linuxbrew/.linuxbrew/bin/bun \
	"$HOME/.local/share/mise/shims/bun" "$HOME/.bun/bin/bun"; do
	if command -v "$bun" >/dev/null 2>&1; then exec "$bun" "$dir/commit-convention.ts" "$@"; fi
done
echo "commit-convention: no bun found, refusing to commit unchecked." >&2
echo "commit-convention: run make apps, or skip this repo: git config hook.commit-convention.enabled false" >&2
exit 1
