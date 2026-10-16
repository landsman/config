#!/usr/bin/env bash
# Checks that a layered skill's list and its detail files agree, the check
# writing-for-agents.md asks for when the two are not generated from one source.
# The detail files are the ones SKILL.md opens with an awk command. Every `## `
# section in them must be named in SKILL.md — by a list item that starts with its
# identifier (C9, V4, P7), so a range like C8–C19 in prose does not cover a
# dropped item, or, without one, by its title in backticks — and every identifier
# SKILL.md uses must have a section. Numbered sections (`## 4. `) follow the list's own
# numbering and are not matched by name.
#
#   skill-sections.sh check <skill-dir>    one line per mismatch, exit 1 on any
#   skill-sections.sh all <skills-dir>     check every skill with detail files
set -euo pipefail

check() {
	local dir=${1%/} rc=0 file heading id prefix
	local skill="$dir/SKILL.md"
	[ -f "$skill" ] || { echo "$dir: no SKILL.md"; return 1; }
	while IFS= read -r file; do
		if [ ! -f "$dir/$file" ]; then
			echo "$dir: SKILL.md opens $file, which does not exist"
			rc=1
			continue
		fi
		while IFS= read -r heading; do
			id=${heading%% *}
			if [[ $id =~ ^[A-Z]+[0-9]+$ ]]; then
				grep -qE "^[[:space:]]*[-*][[:space:]]+(\*\*)?$id([^0-9]|$)" "$skill" ||
					{ echo "$dir: $file has $id, no list item in SKILL.md starts with it"; rc=1; }
			elif [[ ! $id =~ ^[0-9]+\.$ ]]; then
				grep -qF "\`$heading\`" "$skill" ||
					{ echo "$dir: $file has \"$heading\", SKILL.md does not list it"; rc=1; }
			fi
		done < <(sed -n 's/^## //p' "$dir/$file")
		while IFS= read -r prefix; do
			while IFS= read -r id; do
				grep -qE "^## $id " "$dir/$file" ||
					{ echo "$dir: SKILL.md names $id, $file has no such section"; rc=1; }
			done < <(grep -oE "(^|[^A-Za-z0-9])${prefix}[0-9]+" "$skill" | grep -oE "${prefix}[0-9]+" | sort -u)
		done < <(sed -n 's/^## \([A-Z][A-Z]*\)[0-9][0-9]* .*/\1/p' "$dir/$file" | sort -u)
	done < <(grep -oE "awk '[^']*' [^ ]+" "$skill" | awk '{print $NF}' | xargs -n1 basename | sort -u)
	return $rc
}

all() {
	local rc=0 dir
	for dir in "${1%/}"/*/; do
		grep -qs "awk '" "$dir/SKILL.md" || continue
		check "$dir" || rc=1
	done
	return $rc
}

case "${1:-}" in
check) check "$2" ;;
all) all "$2" ;;
*)
	echo "usage: $0 check <skill-dir> | all <skills-dir>" >&2
	exit 2
	;;
esac
