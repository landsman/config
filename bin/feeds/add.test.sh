#!/usr/bin/env bash
# Self-check for ./add.py. No framework: it builds a throwaway OPML file and a
# throwaway feed, runs the real script against them, and asserts on what the
# file holds afterwards. No network — the feeds it reads are file:// URLs, so
# this is the same answer on a runner and on a plane.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/add.py"
root="$(cd "$here/../.." && pwd)"
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

# Read one attribute out of the OPML, by feed URL. Doubles as the parse check:
# a file the script has corrupted fails here rather than returning something.
attr() {  # attr <file> <xmlUrl> <attribute>
	python3 -c 'import sys,xml.etree.ElementTree as ET
o=[o for o in ET.parse(sys.argv[1]).iter("outline") if o.get("xmlUrl")==sys.argv[2]]
print(o[0].get(sys.argv[3]) if o else "")' "$@"
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
check "adds the feed" "Example" "$(attr "$opml" https://example.com/rss.xml text)"
check "sets title as well as text" "Example" "$(attr "$opml" https://example.com/rss.xml title)"
check "marks it type=rss" "rss" "$(attr "$opml" https://example.com/rss.xml type)"

# == the same feed twice
out=$("$script" "$opml" https://example.com/rss.xml "Example" 2>&1 || true)
check "refuses a duplicate" "already there: Example" "$out"
check "and adds nothing" 1 "$(grep -c '<outline' "$opml")"

# == the characters a sed append would corrupt
# An & in the URL and an apostrophe in the title are both ordinary in real
# feeds, and both make the file unparseable if they go in raw. attr() parses,
# so these two rows failing is what an unescaped write looks like.
"$script" "$opml" 'https://example.com/feed?a=1&b=2' "Bob's & Alice's" > /dev/null
check "escapes & in the url" "Bob's & Alice's" "$(attr "$opml" 'https://example.com/feed?a=1&b=2' text)"
check "file still parses" 2 "$(python3 -c 'import sys,xml.etree.ElementTree as ET
print(len(list(ET.parse(sys.argv[1]).iter("outline"))))' "$opml")"

# == the title read off the feed itself
cat > "$tmp/rss.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>  Some RSS Feed  </title></channel></rss>
EOF
"$script" "$opml" "file://$tmp/rss.xml" > /dev/null
check "reads the title from an RSS feed" "Some RSS Feed" "$(attr "$opml" "file://$tmp/rss.xml" text)"

cat > "$tmp/atom.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"><title>Some Atom Feed</title></feed>
EOF
"$script" "$opml" "file://$tmp/atom.xml" > /dev/null
check "reads the title from an Atom feed" "Some Atom Feed" "$(attr "$opml" "file://$tmp/atom.xml" text)"

check "ends with a newline" "" "$(tail -c1 "$opml")"

# == the tracked list, which nothing else parses
# `make feed` is the only thing that reads shared/feeds.opml, so a hand-edit
# that broke it would otherwise surface the next time one is added.
check "shared/feeds.opml parses, every outline has a url" "" \
	"$(python3 -c 'import sys,xml.etree.ElementTree as ET
print("\n".join(o.get("text","?") for o in ET.parse(sys.argv[1]).iter("outline") if not o.get("xmlUrl")))' \
	"$root/shared/feeds.opml")"

echo
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
