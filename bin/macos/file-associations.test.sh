#!/usr/bin/env bash
# Self-check for ./file-associations.sh. Merges a fixture list into a fixture
# plist (LS_LIST, LS_PLIST) and runs --dry-run behind a `defaults` stub, so
# nothing on the developer's Mac is re-assigned by `make qa`.
set -eu

[ "$(uname -s)" = Darwin ] || { echo "macOS only (PlistBuddy) - skipped"; exit 0; }

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/file-associations.sh"
shipped="$here/file-associations.conf"
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
has()      { grep -c "$2" "$1" || true; }

# One of each kind, plus the comment and blank lines the parser has to survive.
cat > "$tmp/list.conf" <<'EOF'
# a comment

ext     sql          com.sublimetext.4
uti     public.html  com.google.chrome
scheme  https        com.google.chrome
EOF

# The same three, claimed by someone else, plus one entry nobody is touching.
cat > "$tmp/fixture.plist" <<'EOF'
{ LSHandlers = (
	{ LSHandlerContentTag = sql; LSHandlerContentTagClass = "public.filename-extension"; LSHandlerRoleAll = "com.apple.TextEdit"; },
	{ LSHandlerContentType = "public.html"; LSHandlerRoleAll = "com.apple.Safari"; },
	{ LSHandlerURLScheme = https; LSHandlerRoleAll = "com.apple.Safari"; },
	{ LSHandlerContentType = "public.mpeg-4"; LSHandlerRoleAll = "org.videolan.vlc"; }
); }
EOF

# The point of the stubs: --dry-run must reach neither the preferences nor
# LaunchServices, or a broken guard rewrites the file associations of whoever
# ran `make qa`.
printf '#!/bin/sh\necho "STUB CALLED: $*"\nexit 1\n' > "$tmp/defaults"
cp "$tmp/defaults" "$tmp/osascript"
chmod +x "$tmp/defaults" "$tmp/osascript"
run() { PATH="$tmp:$PATH" LS_LIST="$1" LS_PLIST="$2" "$script" --dry-run; }

run "$tmp/list.conf" "$tmp/fixture.plist" > "$tmp/out.plist"
check "dry run touches nothing"      '' "$(grep 'STUB CALLED' "$tmp/out.plist" || true)"

# The merge is the extension half only: a UTI and a scheme are set through
# LaunchServices afterwards, which rewrites their entries itself.
check "the extension is taken over"  '1' "$(has "$tmp/out.plist" 'com.sublimetext.4')"
check "the stale handler is gone"    '0' "$(has "$tmp/out.plist" 'com.apple.TextEdit')"
check "the merge leaves the rest"    '2' "$(has "$tmp/out.plist" 'com.apple.Safari')"
check "and writes no UTI or scheme"  '0' "$(has "$tmp/out.plist" 'com.google.chrome')"
check "the untouched entry survives" '1' "$(has "$tmp/out.plist" 'org.videolan.vlc')"
check "no entry is left over"        '4' "$(handlers "$tmp/out.plist")"
# `.sql` instead of `sql` in the list would write an entry macOS never matches.
check "extensions carry no dot"      '0' \
	"$(plutil -p "$tmp/out.plist" | grep -c '"LSHandlerContentTag" => "\.' || true)"
# An extension is matched by tag *and* tag class; a UTI or scheme has neither.
check "only the extension is tagged" '1' \
	"$(plutil -p "$tmp/out.plist" | grep -c 'LSHandlerContentTagClass' || true)"

# Applied twice — on a machine already set up, or just a second `make macos`.
run "$tmp/list.conf" "$tmp/out.plist" > "$tmp/twice.plist"
check "rerunning changes nothing"    '4' "$(handlers "$tmp/twice.plist")"

# A Mac where nothing was ever re-assigned has no plist to merge into.
run "$tmp/list.conf" "$tmp/none.plist" > "$tmp/fresh.plist"
check "a missing plist is created"   '1' "$(handlers "$tmp/fresh.plist")"

# A typo in the kind column would otherwise write an entry LaunchServices ignores,
# which looks exactly like the setting not sticking.
printf 'utl public.html com.google.chrome\n' > "$tmp/bad.conf"
out=$(run "$tmp/bad.conf" "$tmp/fixture.plist" 2>&1) && rc=0 || rc=$?
check "an unknown kind is refused"   '1' "$rc"
check "and says which one"           '1' "$(grep -c "unknown kind 'utl'" <<<"$out")"

# The list this actually ships with: a rename or a stray edit turns it into a
# runtime failure on a fresh Mac and nowhere else.
check "the shipped list exists" 'yes' "$([ -f "$shipped" ] && echo yes || echo no)"
check "every shipped line is kind + what + bundle id" '' \
	"$(awk '/^[[:space:]]*(#|$)/ {next}
		NF != 3 || $1 !~ /^(ext|uti|scheme)$/ || $3 !~ /\./ {print FILENAME": "$0}' "$shipped")"
run "$shipped" "$tmp/fixture.plist" > "$tmp/shipped.plist"
check "and its extensions merge" "$(grep -cE '^[[:space:]]*ext' "$shipped")" \
	"$(plutil -p "$tmp/shipped.plist" | grep -c 'LSHandlerContentTagClass' || true)"

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
