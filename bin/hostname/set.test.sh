#!/usr/bin/env bash
# Self-check for ./set.sh. Only the two subcommands that touch nothing are
# called — `apply` needs root and would rename the machine running the test.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
script=$here/set.sh
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

# == the real table
check "names Omarchy on the T480" "T480-omarchy" "$("$script" name t480 omarchy)"
check "names Kubuntu by its install, not its os id" "T480-kubuntu" "$("$script" name t480 ubuntu)"
# A row with a missing or extra column matches nothing, or matches with the
# wrong name, and nothing says so until that install is booted.
check "every row has three columns" "" \
	"$(awk '!/^[[:space:]]*(#|$)/ && NF != 3' "$here/names.conf")"

# == lookup rules, against a fixture so they do not depend on today's rows
cat > "$tmp/names.conf" <<'EOF'
# t480    arch       Commented-out
t480    omarchy    T480-omarchy
  x1    ubuntu     X1-kubuntu
EOF
export HOSTNAME_LIST=$tmp/names.conf
check "matches an indented row" "X1-kubuntu" "$("$script" name x1 ubuntu)"
check "skips a commented-out row" "missing" "$("$script" name t480 arch || echo missing)"
check "does not match part of a device" "missing" "$("$script" name t48 omarchy || echo missing)"
check "fails on an empty device" "missing" "$("$script" name '' omarchy || echo missing)"
unset HOSTNAME_LIST

# == /etc/hosts
debian=$(printf '127.0.0.1\tlocalhost\n127.0.1.1\tT480.home T480\n# 127.0.1.1 old\n')
check "replaces the Debian 127.0.1.1 line, domain and all" \
	"$(printf '127.0.0.1\tlocalhost\n127.0.1.1\tT480-kubuntu\n# 127.0.1.1 old\n')" \
	"$(echo "$debian" | "$script" hosts T480-kubuntu)"
arch=$(printf '127.0.0.1\tlocalhost\n::1\tlocalhost\n')
check "adds nothing where there is no such line" "$arch" "$(echo "$arch" | "$script" hosts T480-omarchy)"

check "refuses an unknown subcommand" "2" "$("$script" rename x >/dev/null 2>&1; echo $?)"

echo
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
