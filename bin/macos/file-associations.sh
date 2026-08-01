#!/usr/bin/env bash
# Which app opens a file extension — Finder's "Open with… > Change All", which
# stow cannot reach and `defaults write` cannot express as a key: macOS keeps
# every association in one LSHandlers array, one dict per handler, inside
# ~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist.
#
# That array is not committed whole the way symbolichotkeys.plist is. Most of it
# is per-machine noise — a URL-scheme entry for every app that ever registered
# one, on the Mac that happens to have it installed. So only the extensions
# listed below are written, and every other entry in the array is carried across
# untouched.
#
# duti is the usual tool for this and cannot do it. For an extension no app
# claims a UTI for — .sql is one — duti derives a dynamic UTI and LaunchServices
# rejects it: `failed to set … as handler for dyn.ah62d4qmxhk2x465vru (-50)`.
# Finder writes an LSHandlerContentTag entry instead, so that is what this writes.
#
# To add one: set it in Finder (Get Info > Open with > Change All), then read the
# bundle id back out of the array and paste the pair into the list —
#   /usr/libexec/PlistBuddy -c 'Print :LSHandlers' \
#     ~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist
#
# usage: file-associations.sh [--dry-run]   # --dry-run prints the merged plist
set -eu

# extension  bundle id
# ponytail: extensions only. Handlers keyed by UTI (public.html) or URL scheme
# (https) are the "default browser / default mail app" question, which macOS
# also asks in System Settings — a different list, added when it is wanted.
associations="
sql com.sublimetext.4
"

[ "${1:-}" != "--dry-run" ] || DRY_RUN=1
: "${DRY_RUN:=}"
# Overridable so the test can merge into a fixture instead of the real prefs.
: "${LS_PLIST:=$HOME/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
work="$tmp/handlers.plist"

# A Mac where nothing has ever been re-assigned has no plist at all yet.
if [ -f "$LS_PLIST" ]; then cp "$LS_PLIST" "$work"; else echo '{ LSHandlers = (); }' > "$work"; fi
plutil -convert xml1 "$work" >/dev/null

pb() { /usr/libexec/PlistBuddy -c "$1" "$work" 2>/dev/null; }

# PlistBuddy has no "how long is this array", so count upwards until Print fails.
count() {
	n=0
	while pb "Print :LSHandlers:$n" >/dev/null; do n=$((n + 1)); done
	echo "$n"
}

pb "Print :LSHandlers" >/dev/null || pb "Add :LSHandlers array" >/dev/null

while read -r ext bundle; do
	[ -n "$ext" ] || continue
	# Drop whatever claims the extension today — LaunchServices takes the first
	# match, so a leftover entry would win over the one added below. Backwards,
	# because deleting index i renumbers everything above it.
	i=$(count)
	while [ "$i" -gt 0 ]; do
		i=$((i - 1))
		if [ "$(pb "Print :LSHandlers:$i:LSHandlerContentTag" || true)" = "$ext" ]; then
			pb "Delete :LSHandlers:$i" >/dev/null
		fi
	done
	# LSHandlerModificationDate and LSHandlerPreferredVersions are Finder's own
	# bookkeeping and are left out: LaunchServices reads the three keys below.
	n=$(count)
	pb "Add :LSHandlers:$n dict" >/dev/null
	pb "Add :LSHandlers:$n:LSHandlerContentTag string $ext" >/dev/null
	pb "Add :LSHandlers:$n:LSHandlerContentTagClass string public.filename-extension" >/dev/null
	pb "Add :LSHandlers:$n:LSHandlerRoleAll string $bundle" >/dev/null
	[ -n "$DRY_RUN" ] || echo "$ext -> $bundle"
done <<EOF
$associations
EOF

if [ -n "$DRY_RUN" ]; then
	plutil -convert xml1 -o - "$work"
	exit 0
fi

defaults import com.apple.LaunchServices/com.apple.launchservices.secure "$work"

# LaunchServices reads that plist once and caches it, so without this the change
# lands at the next login instead of now. Private, slow (it re-scans every app
# bundle), hence the full path and the `|| true`: if it is gone or fails, the
# preference is still written and a logout still applies it.
lsreg=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$lsreg" ] && "$lsreg" -kill -r -domain local -domain system -domain user >/dev/null 2>&1 || true
killall Finder 2>/dev/null || true

echo "applied"
