#!/usr/bin/env bash
# Self-check for ./file-associations.sh. Merges into a fixture instead of the
# real prefs (LS_PLIST) and runs --dry-run behind a `defaults` stub, so nothing
# on the developer's Mac is re-assigned by `make qa`.
set -eu

[ "$(uname -s)" = Darwin ] || { echo "macOS only (PlistBuddy) - skipped"; exit 0; }

script="$(cd "$(dirname "$0")" && pwd)/file-associations.sh"
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

# Counted as array elements, not as LSHandlerRoleAll keys: a real entry carries a
# second one nested inside LSHandlerPreferredVersions, so that would count double.
handlers() { plutil -p "$1" | grep -cE '^ +[0-9]+ => \{' || true; }
tagged()   { plutil -p "$1" | grep -c "\"LSHandlerContentTag\" => \"$2\"" || true; }

# Three entries in the shapes macOS actually stores: a URL scheme, an extension
# already claimed by someone else, and a content type.
cat > "$tmp/fixture.plist" <<'EOF'
{ LSHandlers = (
	{ LSHandlerURLScheme = https; LSHandlerRoleAll = "com.google.chrome"; },
	{ LSHandlerContentTag = sql; LSHandlerContentTagClass = "public.filename-extension"; LSHandlerRoleAll = "com.apple.TextEdit"; },
	{ LSHandlerContentType = "public.mpeg-4"; LSHandlerRoleAll = "org.videolan.vlc"; }
); }
EOF

# The point of the stub: --dry-run must not reach the real binary, or a broken
# guard rewrites the file associations of whoever ran `make qa`.
printf '#!/bin/sh\necho "STUB CALLED: $*"\nexit 1\n' > "$tmp/defaults"
chmod +x "$tmp/defaults"
run() { PATH="$tmp:$PATH" LS_PLIST="$1" "$script" --dry-run; }

run "$tmp/fixture.plist" > "$tmp/out.plist"
check "dry run never calls defaults" '' "$(grep 'STUB CALLED' "$tmp/out.plist" || true)"

# The whole point of the merge: replace the entry that claims .sql, keep the rest.
check "one handler claims sql"        '1' "$(tagged "$tmp/out.plist" sql)"
check "the stale one is gone"         '0' "$(grep -c 'com.apple.TextEdit' "$tmp/out.plist" || true)"
check "sublime took it over"          '1' "$(grep -c 'com.sublimetext.4' "$tmp/out.plist" || true)"
check "the URL scheme survives"       '1' "$(grep -c 'com.google.chrome' "$tmp/out.plist" || true)"
check "the content type survives"     '1' "$(grep -c 'org.videolan.vlc' "$tmp/out.plist" || true)"
check "no entry is left over"         '3' "$(handlers "$tmp/out.plist")"
# `.sql` instead of `sql` in the list would write an entry macOS never matches.
check "extensions carry no dot"       '0' "$(plutil -p "$tmp/out.plist" | grep -c '"LSHandlerContentTag" => "\.' || true)"

# Applied twice — on a machine already set up, or just a second `make macos`.
run "$tmp/out.plist" > "$tmp/twice.plist"
check "rerunning changes nothing"     '3' "$(handlers "$tmp/twice.plist")"
check "and does not duplicate sql"    '1' "$(tagged "$tmp/twice.plist" sql)"

# A Mac where nothing was ever re-assigned has no plist to merge into.
run "$tmp/none.plist" > "$tmp/fresh.plist"
check "a missing plist is created"    '1' "$(handlers "$tmp/fresh.plist")"

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
