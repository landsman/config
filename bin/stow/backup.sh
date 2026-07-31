#!/usr/bin/env bash
# Move whatever a stow package is about to collide with out of the way.
#
#   backup.sh <stow-dir> <package>
#
# stow refuses to overwrite a real file and gives up on the *whole* package when
# it finds one, so on a fresh machine `make stow` would stop at the first
# hand-written dotfile. This asks stow which files those are (--simulate writes
# nothing), renames each to <file>.bak.<timestamp> and says so. Nothing is
# deleted: if the machine's version was the better one it is still sitting next
# to the symlink stow puts there afterwards.
#
# Only real files are reported by stow this way. A symlink already pointing into
# the repo is stow's own and is left alone, which is what keeps `make restow`
# from making a backup on every run.
set -eu

dir=${1:?usage: backup.sh <stow-dir> <package>}
pkg=${2:?usage: backup.sh <stow-dir> <package>}
stamp=$(date +%Y%m%d%H%M%S)

# Two expressions, because the two stow versions this repo runs on word the same
# conflict differently: 2.4 (Homebrew) says "cannot stow X over existing target Y
# since ...", 2.3 (Ubuntu) says "existing target is neither a link nor a
# directory: Y". Matching only one of them looks perfectly fine on the machine
# you wrote it on and silently does nothing on the other — CI caught exactly
# that. A `-e` per phrasing rather than one alternation, so a third wording is
# one more line.
stow --no-folding -t "$HOME" -d "$dir" --simulate "$pkg" 2>&1 \
| sed -n \
	-e 's/.* over existing target \(.*\) since neither a link.*/\1/p' \
	-e 's/.*existing target is neither a link nor a directory: //p' \
| while IFS= read -r f; do
	# Guarded rather than trusted: this runs `mv` on a path parsed out of
	# another program's prose. An empty capture would make it `mv "$HOME/"`,
	# and a wording change upstream is exactly how that would happen.
	[ -n "$f" ] || continue
	[ -f "$HOME/$f" ] || continue
	[ ! -L "$HOME/$f" ] || continue
	if mv "$HOME/$f" "$HOME/$f.bak.$stamp"; then
		echo "NOTE: ~/$f was a real file - kept as ~/$f.bak.$stamp, the repo's version is now linked there"
	else
		# Reported, not fatal: stow is about to fail on this file anyway and
		# its own message is the clearer one. Silence here would look like a
		# successful backup.
		echo "WARNING: could not back up ~/$f - stow will refuse to link it" >&2
	fi
done
