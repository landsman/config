#!/usr/bin/env bash
# Give this install the hostname ./names.conf lists for it.
#
#   set.sh apply <device>          look the install up and name it (root)
#   set.sh name <device> <os-id>   print the hostname a row gives, or fail
#   set.sh hosts <hostname>        rewrite a hosts file from stdin to stdout
#
# A multi-boot machine is one piece of hardware under several installs. Named
# the same, a prompt, an SSH session and the router's client list cannot tell
# which one is booted.
#
# Two files change, and the second only on some distros. hostnamectl writes
# /etc/hostname. Debian's installer also puts the name in /etc/hosts as a
# 127.0.1.1 line, which nothing updates afterwards: left stale, sudo warns on
# every run that it cannot resolve the host. Arch writes no such line, so the
# line is replaced when it is there and never added when it is not.
#
# `name` and `hosts` touch nothing, which is what ./set.test.sh calls.
set -eu

: "${HOSTNAME_LIST:=$(cd "$(dirname "$0")" && pwd)/names.conf}"

usage() {
	echo "usage: set.sh apply <device> | name <device> <os-id> | hosts <hostname>" >&2
	exit 2
}

name() {  # name <device> <os-id>
	# Whole-field matches, so t48 does not pick up the t480 row, and a
	# commented-out row is skipped before its fields are looked at.
	awk -v d="$1" -v o="$2" '
		/^[[:space:]]*(#|$)/ { next }
		$1 == d && $2 == o { print $3; found = 1; exit }
		END { exit !found }' "$HOSTNAME_LIST"
}

hosts() {  # hosts <hostname>
	# The whole line, not a substitution of the old name: the old name is
	# whatever the installer was given, possibly with a domain after it, and
	# reading it back out is the step that would go wrong.
	awk -v h="$1" '$1 == "127.0.1.1" { print "127.0.1.1\t" h; next } { print }'
}

apply() {  # apply <device>
	[ "$(uname -s)" = Linux ] || { echo "Linux only - skipped"; exit 0; }
	os=$(. /etc/os-release && echo "${ID:-}")
	want=$(name "$1" "$os") \
		|| { echo "no row in bin/hostname/names.conf for device '$1' on '$os' - add one" >&2; exit 1; }

	if [ "$(cat /etc/hostname 2>/dev/null)" = "$want" ]; then
		echo "already named: $want"
	else
		sudo hostnamectl set-hostname "$want"
		echo "hostname: $want"
	fi

	tmp=$(mktemp)
	trap 'rm -f "$tmp"' EXIT
	hosts "$want" < /etc/hosts > "$tmp"
	cmp -s /etc/hosts "$tmp" && return
	# Printed before sudo asks, so a line worth keeping can still be saved.
	diff -u /etc/hosts "$tmp" || true
	sudo install -m 644 -o root -g root "$tmp" /etc/hosts
}

case "${1:-}" in
	apply) [ $# -eq 2 ] || usage; apply "$2" ;;
	name)  [ $# -eq 3 ] || usage; name "$2" "$3" ;;
	hosts) [ $# -eq 2 ] || usage; hosts "$2" ;;
	*)     usage ;;
esac
