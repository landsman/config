#!/usr/bin/env bash
# Runs forbidden-names.ts, and exists only to find bun.
#
# git hooks run from wherever git was started: a terminal, but also an IDE, a GUI
# client or an agent, and those inherit a PATH that often has neither brew nor
# mise on it. A `#!/usr/bin/env bun` shebang would then fail, and a failing
# pre-commit hook means no commits at all — so the search for an interpreter is
# written down here instead of being left to whoever launched git. .gitconfig
# keeps pointing at this path, so nothing on any machine needs rewiring.
#
# Fail closed, like the rest of this check: a machine with no bun cannot commit
# until it has one, rather than committing unchecked. Skip a repo on purpose with
#   git config hook.forbidden-names.enabled false
set -euo pipefail
dir=$(cd "$(dirname "$0")" && pwd)
for bun in bun /opt/homebrew/bin/bun /home/linuxbrew/.linuxbrew/bin/bun \
	"$HOME/.local/share/mise/shims/bun" "$HOME/.bun/bin/bun"; do
	if command -v "$bun" >/dev/null 2>&1; then exec "$bun" "$dir/forbidden-names.ts" "$@"; fi
done
echo "forbidden-names: no bun found, refusing to commit unchecked." >&2
echo "forbidden-names: run make apps, or skip this repo: git config hook.forbidden-names.enabled false" >&2
exit 1
