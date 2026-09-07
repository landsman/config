#!/usr/bin/env bash
# Self-check for ./clone.sh. No network and no clone: `git` is stubbed on PATH,
# and the test asserts on the command lines the script would have run.
set -eu

script="$(cd "$(dirname "$0")" && pwd)/clone.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

check() {  # check <name> <expected> <actual>
	if [ "$2" = "$3" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1"; echo "  expected: $2"; echo "  actual:   $3"; fails=$((fails + 1))
	fi
}

mkdir -p "$tmp/bin"
cat > "$tmp/bin/git" <<'STUB'
#!/usr/bin/env bash
echo "git $*" >> "$GIT_LOG"
# A clone has to leave a repo behind, or the second run below cannot tell a
# fresh machine from one that already has the clone.
if [ "${1:-}" = clone ]; then
	for a in "$@"; do case $a in -*) ;; *) last=$a;; esac; done
	mkdir -p "$last/.git"
fi
STUB
chmod +x "$tmp/bin/git"
export PATH="$tmp/bin:$PATH"

# HOME is redirected because the script defaults its root to ~/projects, and a
# test that forgot to pass one would otherwise pull the real clones.
export HOME="$tmp/home"
root="$tmp/projects"

export GIT_LOG="$tmp/fresh.log"; : > "$GIT_LOG"
"$script" "$root" >/dev/null

check "github docs cloned shallow and sparse" \
	"git clone --depth 1 --filter=blob:none --sparse https://github.com/github/docs.git $root/github/github_docs" \
	"$(grep 'github/docs.git' "$GIT_LOG")"
check "the transcluded snippets are in the checkout" \
	"git -C $root/github/github_docs sparse-checkout set content/actions data/reusables/actions data/variables" \
	"$(grep sparse-checkout "$GIT_LOG")"

# The one that would silently break the rule: --depth 1 leaves no v16.0 branch
# to switch to, and the Forgejo docs are read per version.
check "forgejo docs cloned whole, so the version branches exist" \
	"git clone --filter=blob:none https://codeberg.org/forgejo/docs.git $root/codeberg/forgejo/docs" \
	"$(grep 'forgejo/docs.git' "$GIT_LOG")"

export GIT_LOG="$tmp/again.log"; : > "$GIT_LOG"
"$script" "$root" >/dev/null

check "a second run clones nothing" 0 "$(grep -c ' clone ' "$GIT_LOG" || true)"
check "a second run fast-forwards both" 2 "$(grep -c 'pull --ff-only' "$GIT_LOG" || true)"

# A directory that is not a clone is somebody's work, not a place to clone into.
rm -rf "$root/codeberg/forgejo/docs/.git"
export GIT_LOG="$tmp/occupied.log"; : > "$GIT_LOG"
out=$("$script" "$root" 2>&1 >/dev/null)
check "an occupied path is left alone" 0 "$(grep -c 'forgejo/docs.git' "$GIT_LOG" || true)"
check "and says so" 1 "$(printf '%s\n' "$out" | grep -c 'left alone' || true)"

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
echo "all ok"
