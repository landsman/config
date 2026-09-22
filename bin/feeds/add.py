#!/usr/bin/env python3
"""Add one feed to an OPML subscription list, in place.

    add.py <opml> <url> [title]

Python rather than an append with sed, because a feed URL routinely carries a
`&` and a title routinely carries an apostrophe — both have to be escaped to
keep the file valid XML, and ElementTree is the half of the standard library
that already knows that.
"""
import sys
import urllib.request
import xml.etree.ElementTree as ET

ATOM_TITLE = "{http://www.w3.org/2005/Atom}title"


def feed_title(url):
    # Doubles as the check that the URL is a feed at all: a typo, an HTML page
    # or a 404 fails here, rather than silently six months later in the reader.
    # The User-Agent is not decoration — a bare urllib request is what several
    # CDNs answer with 403, and that reads like a dead feed.
    req = urllib.request.Request(url, headers={"User-Agent": "feeds/add.py"})
    with urllib.request.urlopen(req, timeout=10) as response:
        root = ET.parse(response).getroot()
    for path in ("./channel/title", ATOM_TITLE):
        found = root.find(path)
        # `if found:` is False for an element with no children, which a <title>
        # never has — the one ElementTree trap worth spelling out.
        if found is not None and found.text:
            return found.text.strip()
    raise SystemExit(f"no <title> in {url} - pass one as the third argument")


def add(path, url, title=None):
    tree = ET.parse(path)
    body = tree.getroot().find("body")
    for outline in body.iter("outline"):
        if outline.get("xmlUrl") == url:
            raise SystemExit(f"already there: {outline.get('text')}")
    title = title or feed_title(url)
    # ponytail: no htmlUrl — a reader subscribes from xmlUrl and nothing here
    # reads the site link. Add the <link> lookup when something does.
    ET.SubElement(body, "outline", type="rss", text=title, title=title, xmlUrl=url)
    ET.indent(tree, "  ")
    # ET stops at the closing root tag, so without this the file ends mid-line
    # and every later diff opens with "\ No newline at end of file".
    tree.getroot().tail = "\n"
    tree.write(path, encoding="UTF-8", xml_declaration=True)
    print(f"added: {title}")


if __name__ == "__main__":
    if not 2 <= len(sys.argv) - 1 <= 3:
        raise SystemExit(__doc__)
    add(*sys.argv[1:])
