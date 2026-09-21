#!/usr/bin/env bash
# Apply the Chrome settings that Google does not sync.
#
# Chrome syncs bookmarks, extensions, passwords and most of the Settings page,
# but a handful of window-chrome toggles are per-installation and never leave
# the machine — vertical tabs is the obvious one. Those are what this writes.
#
# Not a guess: chrome/browser/sync/prefs/chrome_syncable_prefs_database.cc has
#   // kVerticalTabsEnabled = 100330, (no longer synced)
# so that one had a sync id and Google took it away; the other three keys are
# absent from that file entirely, having never had one. Two such tombstones
# exist in those 2300 lines, so it is a decision rather than an oversight — and
# it is the line to re-read if a new Chrome starts syncing this after all.
#
# A script and not a stow package: Chrome keeps them in `Default/Preferences`,
# one JSON blob that also holds site permissions, engagement scores, an upload
# seed and a window rectangle. Symlinking that into git would track the noise
# and leak the rest, so only the keys in prefs.py are written and everything
# else is left as the machine has it. Same reasoning as bin/macos/defaults.sh.
#
# To add a setting: copy Preferences aside, flip the toggle in Chrome, quit it,
# then diff — Chrome only flushes the file on exit:
#   cp "$CHROME_PREFS" /tmp/before   # …flip it, quit Chrome…
#   python3 -m json.tool "$CHROME_PREFS" | diff <(python3 -m json.tool /tmp/before) -
# and add the dotted key to PREFS in prefs.py beside it.
#
# usage: prefs.sh [--dry-run]
#
# macOS asks for Full Disk Access on the terminal before this can touch the
# profile at all — see the guard below for why -f alone does not catch it.
set -eu

# Anything unrecognised is refused rather than ignored: a mistyped `--dryrun`
# would otherwise patch the profile for real, which is what the flag is for.
case "${1:-}" in
"")         DRY_RUN= ;;
--dry-run)  DRY_RUN=1 ;;
*)          echo "usage: prefs.sh [--dry-run]" >&2; exit 2 ;;
esac

# The edit itself is prefs.py, next to this file. What stays here is the part
# that has to be shell: the platform's path, and the refusals below.
patch="$(cd "$(dirname "$0")" && pwd)/prefs.py"

# ponytail: the Default profile only. A second profile is a second $CHROME_PREFS
# run, and this repo has never had one.
case "$(uname -s)" in
Darwin) default_prefs="$HOME/Library/Application Support/Google/Chrome/Default/Preferences" ;;
*)      default_prefs="$HOME/.config/google-chrome/Default/Preferences" ;;
esac
: "${CHROME_PREFS:=$default_prefs}"

if [ -n "$DRY_RUN" ]; then
	exec python3 "$patch" --dry-run "$CHROME_PREFS"
fi

[ -f "$CHROME_PREFS" ] || { echo "no Chrome profile at $CHROME_PREFS"; exit 1; }

# -f is not enough on macOS. Chrome's data directory carries com.apple.macl, so
# a terminal without Full Disk Access gets EPERM on read *and* on listing, while
# stat still succeeds — `test -f` says yes and the write then dies on its face.
# Reproduce it with:
#   ls "$HOME/Library/Application Support/Google/Chrome"
# The rename needs the directory, not just the file, hence both checks.
if [ ! -r "$CHROME_PREFS" ] || [ ! -w "$(dirname "$CHROME_PREFS")" ]; then
	echo "cannot read or replace $CHROME_PREFS"
	echo "macOS guards Chrome's profile: System Settings > Privacy & Security >"
	echo "Full Disk Access > add this terminal, then run this again"
	exit 1
fi

# Chrome holds the whole file in memory and rewrites it on exit, so a write made
# while it runs is silently discarded a few hours later — the worst kind of
# no-op. Refuse instead.
if pgrep -x "Google Chrome" >/dev/null 2>&1 || pgrep -x chrome >/dev/null 2>&1; then
	echo "quit Chrome first - it overwrites $CHROME_PREFS on exit"; exit 1
fi

# python3 and not jq: it ships with macOS and with every runner, and jq is not
# in the Brewfile. The temp-file-plus-rename is in there too.
python3 "$patch" "$CHROME_PREFS"

echo "applied - start Chrome"
