#!/usr/bin/env bash
# What pre-push.sh would get wrong silently: a failing check that still lets the
# push through, or checks run in a repo that never opted in. make is a stub that
# logs its call and fails when told to.
set -euo pipefail
hook="$(cd "$(dirname "$0")" && pwd)/pre-push.sh"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

mkdir "$t/bin" "$t/repo"
cat >"$t/bin/make" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$MAKE_LOG"
exit "${MAKE_EXIT:-0}"
EOF
chmod +x "$t/bin/make"
export PATH="$t/bin:$PATH" MAKE_LOG="$t/make.log"
git -C "$t/repo" init -q

push='refs/heads/b 1111111111111111111111111111111111111111 refs/heads/b 0000000000000000000000000000000000000000'
delete='(delete) 0000000000000000000000000000000000000000 refs/heads/b 1111111111111111111111111111111111111111'

fail=0
check() { # behaviour, expected exit, expected make calls, stdin
	: >"$MAKE_LOG"
	rc=0; (cd "$t/repo" && "$hook" origin url <<<"$4" 2>/dev/null) || rc=$?
	calls=$(wc -l <"$MAKE_LOG" | tr -d ' ')
	if [ "$rc" = "$2" ] && [ "$calls" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (exit $rc, make calls $calls)"; fail=1; fi
}

check "a repo without a Makefile is pushed unchecked" 0 0 "$push"
printf 'qa:\n' >"$t/repo/Makefile"
check "a Makefile without a pre-push target is pushed unchecked" 0 0 "$push"
printf 'pre-push: qa\nqa:\n' >"$t/repo/Makefile"
check "a pre-push target runs on a push" 0 1 "$push"
MAKE_EXIT=2 check "a failing pre-push target stops the push" 2 1 "$push"
check "deleting a branch runs nothing" 0 0 "$delete"

exit $fail
