#!/usr/bin/env bash
# Which app opens what — Finder's "Open with… > Change All" and the default
# browser, which stow cannot reach and `defaults write` cannot express as a key:
# macOS keeps every association in one LSHandlers array, one dict per handler, in
# ~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist.
#
# The list itself is ./file-associations.conf, a file of its own because it is
# the part worth reading — this script is just the merge.
#
# That array is not committed whole the way symbolichotkeys.plist is. Most of it
# is per-machine noise: a URL-scheme entry for every app that ever registered
# one, on the Mac that happens to have it installed. So only the associations in
# the list are written, and every other entry is carried across untouched.
#
# Writing that plist is not enough for a UTI or a URL scheme. LaunchServices
# keeps its own copy of those bindings and rebuilding its database does not
# re-read the file, so an app that already claims the type simply keeps it: Pages
# stayed the default for .docx with the plist saying LibreOffice. The API it does
# listen to is LSSetDefault…, reached here through osascript's ObjC bridge, so
# there is still nothing to install.
#
# Extensions are the other way round and are why the plist is written by hand.
# For an extension no app claims a UTI for — .sql is one — that API (and duti,
# which wraps it) derives a dynamic UTI and LaunchServices rejects it: `failed to
# set … dyn.ah62d4qmxhk2x465vru (-50)`. Finder writes an LSHandlerContentTag
# entry instead, so that is what this writes.
#
# To add one: set it in Finder (Get Info > Open with > Change All) or in System
# Settings, then read back what it wrote and copy it into the list —
#   /usr/libexec/PlistBuddy -c 'Print :LSHandlers' \
#     ~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist
#
# usage: file-associations.sh [--dry-run]   # --dry-run prints the merged plist
set -eu

[ "${1:-}" != "--dry-run" ] || DRY_RUN=1
: "${DRY_RUN:=}"
# Both overridable so the test can merge a fixture list into a fixture plist
# rather than into the real preferences.
: "${LS_LIST:=$(cd "$(dirname "$0")" && pwd)/file-associations.conf}"
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

: > "$tmp/launchservices"

written=0
while read -r kind what bundle; do
	case "$kind" in '' | '#'*) continue ;; esac
	[ -n "$bundle" ] || { echo "$LS_LIST: no bundle id for '$what'" >&2; exit 1; }
	case "$kind" in
		# Held back until the merged plist has been imported: they are written to
		# the same file, and importing a copy taken before they ran would undo them.
		uti | scheme) echo "$kind $what $bundle" >> "$tmp/launchservices" ;;
		ext) ;;
		*) echo "$LS_LIST: unknown kind '$kind'" >&2; exit 1 ;;
	esac
	written=$((written + 1))
	[ -n "$DRY_RUN" ] || echo "  $what -> $bundle"
	[ "$kind" = ext ] || continue

	# Drop whatever claims it today, or the old entry sits in the array beside the
	# new one. Backwards, because deleting index i renumbers everything above it.
	i=$(count)
	while [ "$i" -gt 0 ]; do
		i=$((i - 1))
		if [ "$(pb "Print :LSHandlers:$i:LSHandlerContentTag" || true)" = "$what" ]; then
			pb "Delete :LSHandlers:$i" >/dev/null
		fi
	done

	# LSHandlerModificationDate and LSHandlerPreferredVersions are Finder's own
	# bookkeeping and are left out: LaunchServices reads the keys written here.
	n=$(count)
	pb "Add :LSHandlers:$n dict" >/dev/null
	pb "Add :LSHandlers:$n:LSHandlerContentTag string $what" >/dev/null
	pb "Add :LSHandlers:$n:LSHandlerContentTagClass string public.filename-extension" >/dev/null
	pb "Add :LSHandlers:$n:LSHandlerRoleAll string $bundle" >/dev/null
done < "$LS_LIST"

if [ -n "$DRY_RUN" ]; then
	plutil -convert xml1 -o - "$work"
	exit 0
fi

defaults import com.apple.LaunchServices/com.apple.launchservices.secure "$work"

# 0xFFFFFFFF is kLSRolesAll — viewer and editor both, which is what "Change All"
# sets. Both calls return an OSStatus; anything but 0 means it did not take, and
# that is worth stopping on, because it looks exactly like the setting not sticking.
while read -r kind what bundle; do
	case "$kind" in
		uti)    call='$.LSSetDefaultRoleHandlerForContentType($(a[0]), 0xFFFFFFFF, $(a[1]))' ;;
		scheme) call='$.LSSetDefaultHandlerForURLScheme($(a[0]), $(a[1]))' ;;
	esac
	status=$(osascript -l JavaScript \
		-e "ObjC.import('CoreServices'); function run(a) { return $call }" "$what" "$bundle")
	[ "$status" = 0 ] || {
		echo "$what -> $bundle: LaunchServices refused it (OSStatus $status)" >&2; exit 1
	}
done < "$tmp/launchservices"

# LaunchServices reads that plist once and caches it, so without this the change
# lands at the next login instead of now. Private, slow (it re-scans every app
# bundle), hence the full path and the `|| true`: if it is gone or fails, the
# preference is still written and a logout still applies it.
lsreg=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$lsreg" ] && "$lsreg" -kill -r -domain local -domain system -domain user >/dev/null 2>&1 || true
killall Finder 2>/dev/null || true

echo "$written associations from $(basename "$LS_LIST") are now the defaults (listed above); LaunchServices rebuilt and Finder restarted, so they hold immediately"
