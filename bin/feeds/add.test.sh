#!/usr/bin/env bash
# Self-check for ./add.sh. No framework: it builds a throwaway OPML file and a
# throwaway feed, runs the real script against them, and asserts on what the
# file holds afterwards. No network — the feeds it reads are file:// URLs, so
# this is the same answer on a runner and on a plane.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/add.sh"
root="$(cd "$here/../.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

if command -v yq >/dev/null; then
	yq=(yq)
elif command -v mise >/dev/null; then
	yq=(mise x -- yq)
else
	echo "yq not installed - skipped"; exit 0
fi

check() {  # check <name> <expected> <actual>
	if [ "$2" = "$3" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1"; echo "  expected: $2"; echo "  actual:   $3"; fails=$((fails + 1))
	fi
}

# Read one attribute out of the OPML, by feed URL. Doubles as the parse check:
# a file the script has corrupted fails here rather than returning something.
attr() {  # attr <file> <xmlUrl> <key, e.g. +@text>
	URL=$2 ATTR=$3 "${yq[@]}" -p=xml -oy \
		'[.opml.body.outline] | flatten | map(select(."+@xmlUrl" == strenv(URL))) | .[0][strenv(ATTR)] // ""' "$1"
}

opml=$tmp/feeds.opml
cat > "$opml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head>
    <title>Feeds</title>
  </head>
  <body>
  </body>
</opml>
EOF

# == a title given on the command line
"$script" "$opml" https://example.com/rss.xml "Example" > /dev/null
check "adds the feed" "Example" "$(attr "$opml" https://example.com/rss.xml '+@text')"
check "sets title as well as text" "Example" "$(attr "$opml" https://example.com/rss.xml '+@title')"
check "marks it type=rss" "rss" "$(attr "$opml" https://example.com/rss.xml '+@type')"

# == the same feed twice
out=$("$script" "$opml" https://example.com/rss.xml "Example" 2>&1 || true)
check "refuses a duplicate" "already there: Example" "$out"
check "and adds nothing" 1 "$(grep -c '<outline' "$opml")"

# == a second and a third feed
# The row that matters most here. XML cannot say "this is a list", so yq reads
# one <outline> as a map and two as an array, and `+=` on the map *replaces* it
# — valid XML, exit 0, and the list silently shrinks to its newest row. Every
# count below is the guard on that: one add is not evidence, three are.
"$script" "$opml" https://example.com/second.xml "Second" > /dev/null
check "keeps the first feed when adding a second" 2 "$(grep -c '<outline' "$opml")"
"$script" "$opml" https://example.com/third.xml "Third" > /dev/null
check "keeps both when adding a third" 3 "$(grep -c '<outline' "$opml")"
check "the first one is still the first one" "Example" "$(attr "$opml" https://example.com/rss.xml '+@text')"

# == the characters a sed append would corrupt
# An & in the URL and an apostrophe in the title are both ordinary in real
# feeds, and both make the file unparseable if they go in raw. attr() parses,
# so this row failing is what an unescaped write looks like.
"$script" "$opml" 'https://example.com/feed?a=1&b=2' "Bob's & Alice's" > /dev/null
check "escapes & and ' " "Bob's & Alice's" "$(attr "$opml" 'https://example.com/feed?a=1&b=2' '+@text')"
check "file still parses" "valid" "$(xmllint --noout "$opml" 2>&1 && echo valid)"

# == a title that is not passed in, but read off the feed
cat > "$tmp/rss.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>  Some RSS Feed  </title></channel></rss>
EOF
"$script" "$opml" "file://$tmp/rss.xml" > /dev/null
check "reads the title from an RSS feed" "Some RSS Feed" "$(attr "$opml" "file://$tmp/rss.xml" '+@text')"

cat > "$tmp/atom.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"><title>Some Atom Feed</title></feed>
EOF
"$script" "$opml" "file://$tmp/atom.xml" > /dev/null
check "reads the title from an Atom feed" "Some Atom Feed" "$(attr "$opml" "file://$tmp/atom.xml" '+@text')"

check "keeps the xml declaration" "1" "$(grep -c '^<?xml' "$opml")"
check "ends with a newline" "" "$(tail -c1 "$opml")"

# == the tracked list, which nothing else parses
# `make feed` is the only thing that reads the tracked list, so a hand-edit
# that broke it would otherwise surface the next time one is added.
check "shared/.config/feeds.opml parses, every outline has a url" "" \
	"$("${yq[@]}" -p=xml -oy \
		'[.opml.body.outline] | flatten | map(select(. != null) | select(has("+@xmlUrl") | not) | ."+@text" // "?") | .[]' \
		"$root/shared/.config/feeds.opml")"

echo
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
