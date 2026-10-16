#!/usr/bin/env bash
# Self-check for ./tailnet-proxy.sh. nc and tailscale are stubbed on a temp PATH,
# so every branch runs with no network, no tailnet and no real sleeps — which is
# what `make bin-test` needs to pass on a CI runner.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
script=$here/tailnet-proxy.sh
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

# == stubs. nc answers the -z probe from $STUB_NC_CONNECT and, when carrying
# (no -z), prints a marker so the exec path is observable. tailscale answers
# `status` from $STUB_TS_UP. Both read the env the script was run with.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/nc" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-z" ]; then
	[ "${STUB_NC_CONNECT:-no}" = yes ] && exit 0 || exit 1
fi
echo "CARRY $*"
EOF
cat > "$tmp/bin/tailscale" <<'EOF'
#!/usr/bin/env bash
[ "${STUB_TS_UP:-no}" = yes ] && exit 0 || exit 1
EOF
chmod +x "$tmp/bin/nc" "$tmp/bin/tailscale"

# run <extra env> -- capture combined output in OUT and exit status in CODE,
# always with the stubs ahead on PATH and the retries wound right down.
run() {
	OUT=$(env PATH="$tmp/bin:$PATH" TAILNET_SSH_TRIES=2 TAILNET_SSH_RETRY_DELAY=0 \
		"$@" "$script" 2>&1) && CODE=0 || CODE=$?
}

# == reachable: the probe passes and the script hands off to the carrying nc
run STUB_NC_CONNECT=yes TAILNET_SSH_HOST=box.ts.net TAILNET_SSH_PORT=222
check "carries the connection when reachable" "CARRY box.ts.net 222" "$OUT"
check "carry exits 0" "0" "$CODE"

# == host/port from args when the env is unset (the reuse path). Inline, not via
# run(): env assignments and the script's own args cannot share one `env` arg
# list — the first non-NAME=VALUE token would be taken as the command to run.
OUT=$(env PATH="$tmp/bin:$PATH" TAILNET_SSH_TRIES=2 TAILNET_SSH_RETRY_DELAY=0 \
	STUB_NC_CONNECT=yes "$script" arghost argport 2>&1) && CODE=0 || CODE=$?
check "falls back to positional host/port" "CARRY arghost argport" "$OUT"

# == unreachable but the daemon says up: name the check, not a guilty party
run STUB_NC_CONNECT=no STUB_TS_UP=yes TAILNET_SSH_HOST=box.ts.net TAILNET_SSH_PORT=222
check "up-but-unreachable exits 1" "1" "$CODE"
check "up-but-unreachable points at tailscale ping" "found" \
	"$(printf '%s\n' "$OUT" | grep -q 'tailscale ping box.ts.net' && echo found || echo missing)"

# == tailnet down: say so plainly
run STUB_NC_CONNECT=no STUB_TS_UP=no TAILNET_SSH_HOST=box.ts.net TAILNET_SSH_PORT=222
check "tailscale-off exits 1" "1" "$CODE"
check "tailscale-off says to bring it up" "found" \
	"$(printf '%s\n' "$OUT" | grep -q 'Tailscale is off' && echo found || echo missing)"

# == no target at all: refuse with a usable message, do not dial a default
run STUB_NC_CONNECT=yes
check "missing env exits 1" "1" "$CODE"
check "missing env explains itself" "found" \
	"$(printf '%s\n' "$OUT" | grep -q 'set TAILNET_SSH_HOST' && echo found || echo missing)"

echo
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
