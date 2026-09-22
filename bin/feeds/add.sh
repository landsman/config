#!/usr/bin/env bash
# Add one feed to an OPML subscription list, in place.
#
#     add.sh <opml> <url> [title]
#
# The entry point is `make feed`, which owns the prompting. By the time this
# runs the only thing left is the edit.
#
# yq and not sed, because a feed URL routinely carries a `&` and a title
# routinely carries an apostrophe — both have to be escaped to keep the file
# valid XML, and an append with sed writes them raw.
set -euo pipefail

usage() { echo "usage: $(basename "$0") <opml> <url> [title]" >&2; exit 1; }
[ $# -ge 2 ] && [ $# -le 3 ] || usage

opml=$1
url=$2
title=${3:-}

# On PATH when the shell has mise activated, through mise when it has not.
# `make` runs a non-interactive shell that sources neither rc file, so the
# second branch is the normal case here rather than the fallback.
if command -v yq >/dev/null; then
	yq=(yq)
elif command -v mise >/dev/null; then
	yq=(mise x -- yq)
else
	echo "yq not installed - run: make apps, then mise install" >&2
	exit 1
fi

# Every value reaches yq through the environment and `strenv`, never spliced
# into the expression: a quote inside a title would otherwise close the
# expression early and yq would evaluate whatever the title said next.
#
# `[.opml.body.outline] | flatten` is the shape fix, and it is load-bearing in
# both expressions below. XML has no way to say "this is a list", so yq reads
# one <outline> as a map and two as an array — code written against a two-feed
# file breaks on a one-feed file, and vice versa. Wrapping and flattening makes
# both an array, including the empty case.
list='[.opml.body.outline] | flatten | map(select(. != null))'

dupes=$(URL=$url "${yq[@]}" -p=xml -oy \
	"$list | map(select(.\"+@xmlUrl\" == strenv(URL))) | length" "$opml")
if [ "$dupes" != 0 ]; then
	have=$(URL=$url "${yq[@]}" -p=xml -oy \
		"$list | map(select(.\"+@xmlUrl\" == strenv(URL)) | .\"+@text\") | .[0]" "$opml")
	echo "already there: $have" >&2
	exit 1
fi

if [ -z "$title" ]; then
	# Doubles as the check that the URL is a feed at all: a typo, an HTML page
	# or a 404 fails here, rather than silently six months later in the reader.
	# -f so an HTTP error is a failure rather than a page of HTML, -L to follow
	# a redirect, and -A because a bare curl User-Agent is what several CDNs
	# answer with 403 — which reads like a dead feed.
	#
	# One expression covers RSS and Atom because yq does not resolve
	# namespaces: Atom's default xmlns leaves the element named plain `title`.
	title=$(curl -fsSL --max-time 10 -A 'feeds/add.sh' "$url" \
		| "${yq[@]}" -p=xml -oy '(.rss.channel.title // .feed.title // "") | sub("^\s+"; "") | sub("\s+$"; "")')
	[ -n "$title" ] || { echo "no <title> in $url - pass one as the third argument" >&2; exit 1; }
fi

# Assignment and not `+=`. On a file that already holds an outline, `+=`
# overwrites it and leaves one entry behind — valid XML, no error, and the
# feed list quietly shrinks to its newest row. add.test.sh pins this.
#
# ponytail: no htmlUrl — a reader subscribes from xmlUrl and nothing here reads
# the site link. Add the <link> lookup when something does.
TITLE=$title URL=$url "${yq[@]}" -i -p=xml -o=xml \
	".opml.body.outline = ($list
	 + [{\"+@type\": \"rss\", \"+@text\": strenv(TITLE), \"+@title\": strenv(TITLE), \"+@xmlUrl\": strenv(URL)}])" "$opml"

echo "added: $title"
