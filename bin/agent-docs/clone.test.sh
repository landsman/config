#!/usr/bin/env bash
# Self-check for ./clone.sh. No network and no clone: `git` is stubbed on PATH,
# and the test asserts on the command lines the script would have run.
#
# The behaviour cases use a fixture conf rather than repos.conf, so adding a docs
# source stays a one-section edit and moves no number in here. repos.conf gets
# its own case at the end: that it parses, and that every section in it reaches
# git.
set -eu

script="$(cd "$(dirname "$0")" && pwd)/clone.sh"
conf="$(cd "$(dirname "$0")" && pwd)/repos.conf"
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

# One section per shape the conf can take: sparse, whole, and pinned to a tag.
cat > "$tmp/repos.conf" <<'FIXTURE'
# a comment, and a blank line under it

[a/sparse]
url    = https://example.invalid/a.git
sparse = docs data

[b/whole]
url    = https://example.invalid/b.git

[c/pinned]
url    = https://example.invalid/c.git
ref    = v1.2.3
sparse = src/main/antora
FIXTURE

export GIT_LOG="$tmp/fresh.log"; : > "$GIT_LOG"
"$script" "$root" "$tmp/repos.conf" >/dev/null

check "a sparse clone is shallow" \
	"git clone --filter=blob:none --depth 1 --sparse https://example.invalid/a.git $root/a/sparse" \
	"$(grep 'a.git' "$GIT_LOG")"
check "and checks out the named paths" \
	"git -C $root/a/sparse sparse-checkout set docs data" \
	"$(grep 'a/sparse sparse-checkout' "$GIT_LOG")"

# The one that would silently break the Forgejo rule: --depth 1 leaves no v16.0
# branch to switch to, and those docs are read per version.
check "a whole clone keeps its history, so branches exist" \
	"git clone --filter=blob:none https://example.invalid/b.git $root/b/whole" \
	"$(grep 'b.git' "$GIT_LOG")"

check "a pinned clone asks for the ref" \
	"git clone --filter=blob:none --depth 1 --sparse --branch v1.2.3 https://example.invalid/c.git $root/c/pinned" \
	"$(grep 'c.git' "$GIT_LOG")"

export GIT_LOG="$tmp/again.log"; : > "$GIT_LOG"
"$script" "$root" "$tmp/repos.conf" >/dev/null

check "a second run clones nothing" 0 "$(grep -c ' clone ' "$GIT_LOG" || true)"
check "and fast-forwards the two that track a branch" 2 "$(grep -c 'pull --ff-only' "$GIT_LOG" || true)"
check "a pinned clone is fetched at its ref instead" \
	"git -C $root/c/pinned fetch --depth 1 origin v1.2.3" \
	"$(grep 'fetch' "$GIT_LOG")"
check "and left sitting on it" \
	"git -C $root/c/pinned checkout --quiet --detach FETCH_HEAD" \
	"$(grep 'checkout' "$GIT_LOG")"

# A directory that is not a clone is somebody's work, not a place to clone into.
rm -rf "$root/b/whole/.git"
export GIT_LOG="$tmp/occupied.log"; : > "$GIT_LOG"
out=$("$script" "$root" "$tmp/repos.conf" 2>&1 >/dev/null)
check "an occupied path is left alone" 0 "$(grep -c 'b.git' "$GIT_LOG" || true)"
check "and says so" 1 "$(printf '%s\n' "$out" | grep -c 'left alone' || true)"

# The conf is parsed by hand, so the parser is the part that can be wrong. Each
# case writes a broken conf and asserts the script refuses it and clones nothing
# — a typo that half-runs is worse than one that stops.
bad() {  # bad <name> <expected message fragment> <conf body>
	local name=$1 want=$2 body=$3 out
	printf '%s\n' "$body" > "$tmp/bad.conf"
	export GIT_LOG="$tmp/bad.log"; : > "$GIT_LOG"

	if out=$("$script" "$tmp/badroot" "$tmp/bad.conf" 2>&1 >/dev/null); then
		echo "FAIL $name"; echo "  the script accepted it"; fails=$((fails + 1))
		return
	fi
	case $out in
		*"$want"*) echo "ok   $name" ;;
		*) echo "FAIL $name"; echo "  wanted: *$want*"; echo "  got:    $out"; fails=$((fails + 1)) ;;
	esac
	check "  and clones nothing" 0 "$(grep -c . "$GIT_LOG" || true)"
}

bad "a typo in a key is refused" "unknown key 'sparce'" "$(printf '[a/b]\nurl = u\nsparce = x\n')"
bad "a section without a url is refused" "has no url" "[a/b]"
bad "a key outside a section is refused" "before any [section]" "url = u"
bad "a line that is not key = value is refused" "expected 'key = value'" "$(printf '[a/b]\nurl: u\n')"

# repos.conf itself: it parses, and every section in it reaches git. This is the
# one assertion that moves when a source is added, and it moves on its own.
export GIT_LOG="$tmp/real.log"; : > "$GIT_LOG"
"$script" "$tmp/realroot" "$conf" >/dev/null
check "every section of repos.conf is cloned" \
	"$(grep -c '^\[' "$conf")" "$(grep -c ' clone ' "$GIT_LOG" || true)"

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
echo "all ok"
