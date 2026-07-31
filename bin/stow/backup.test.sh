#!/usr/bin/env bash
# Self-check for ./backup.sh. No framework: it builds a throwaway $HOME and a
# throwaway stow package, runs the real script against the real stow, and
# asserts on the files left behind.
set -eu

script="$(cd "$(dirname "$0")" && pwd)/backup.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

command -v stow >/dev/null || { echo "stow not installed - skipped"; exit 0; }

check() {  # check <name> <expected> <actual>
	if [ "$2" = "$3" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1"; echo "  expected: $2"; echo "  actual:   $3"; fails=$((fails + 1))
	fi
}

# The package is built here rather than pointed at shared/, so this tests the
# script and not whatever happens to be tracked today.
pkgdir=$tmp/stow
mkdir -p "$pkgdir/pkg/.config/sub"
echo repo > "$pkgdir/pkg/.config/one.conf"
echo repo > "$pkgdir/pkg/.config/sub/two.conf"
echo repo > "$pkgdir/pkg/.config/with space.conf"

export HOME=$tmp/home
mkdir -p "$HOME/.config/sub"

# == nothing in the way
out=$("$script" "$pkgdir" pkg)
check "says nothing when there is no conflict" "" "$out"

# == real files in the way, including one stow will report on its own line
echo mine1 > "$HOME/.config/one.conf"
echo mine2 > "$HOME/.config/sub/two.conf"
echo mine3 > "$HOME/.config/with space.conf"
out=$("$script" "$pkgdir" pkg)

# Every conflict, not just the first: stow reports them all at once, so a script
# that handled one would still look green against a single-file fixture.
check "backs up all three" 3 "$(ls "$HOME"/.config/*.bak.* "$HOME"/.config/sub/*.bak.* 2>/dev/null | wc -l | tr -d ' ')"
check "keeps the file's content" "mine1" "$(cat "$HOME"/.config/one.conf.bak.*)"
check "reaches into subdirectories" "mine2" "$(cat "$HOME"/.config/sub/two.conf.bak.*)"
check "survives a space in the name" "mine3" "$(cat "$HOME"/.config/with?space.conf.bak.*)"
check "moves, does not copy" "" "$(ls "$HOME/.config/one.conf" 2>/dev/null || true)"
check "says so, once per file" 3 "$(echo "$out" | grep -c '^NOTE: ')"

# == what it left behind is stowable
stow --no-folding -t "$HOME" -d "$pkgdir" pkg
check "stow now succeeds" "repo" "$(cat "$HOME/.config/one.conf")"
check "and the file is a symlink" "yes" "$([ -L "$HOME/.config/one.conf" ] && echo yes || echo no)"

# == a second run over links stow already owns
out=$("$script" "$pkgdir" pkg)
check "leaves its own symlinks alone" "" "$out"
check "so restow makes no new backups" 3 "$(ls "$HOME"/.config/*.bak.* "$HOME"/.config/sub/*.bak.* 2>/dev/null | wc -l | tr -d ' ')"

echo
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
