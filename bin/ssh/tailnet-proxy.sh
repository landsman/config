#!/usr/bin/env bash
# ssh ProxyCommand for a host only reachable over Tailscale — a Forgejo git SSH
# endpoint behind Cloudflare, say, which Cloudflare will not proxy on port 22.
# Point an ssh config Host at it (that file is machine-local, not in this repo):
#
#   Host git-ssh.example
#       User git
#       ProxyCommand ~/projects/landsman/config/bin/ssh/tailnet-proxy.sh
#
# and set the real target in the environment, so no hostname lands in this public
# repo — a ~/.config/bash_aliases.d/*.sh drop-in, the same place the MCP token
# lives (see the Makefile's `claude` target):
#
#   export TAILNET_SSH_HOST=box.tailnet.ts.net
#   export TAILNET_SSH_PORT=222
#
# Why a script and not `nc %h %p` inline: with Tailscale down the bare nc fails
# with "Could not resolve host", which reads like the forge is broken. This
# retries the connect — covering a tailnet still coming up — then says which half
# is actually down, Tailscale or the box.
set -eu

host="${TAILNET_SSH_HOST:-${1:-}}"
port="${TAILNET_SSH_PORT:-${2:-}}"
tries="${TAILNET_SSH_TRIES:-5}"       # the test turns these two down so it does
delay="${TAILNET_SSH_RETRY_DELAY:-1}" # not wait on real sleeps

if [ -z "$host" ] || [ -z "$port" ]; then
	echo "tailnet-proxy: set TAILNET_SSH_HOST and TAILNET_SSH_PORT (or pass host port as args)" >&2
	exit 1
fi

i=1
while [ "$i" -le "$tries" ]; do
	# ponytail: probe then connect is two TCP opens, the first a wasted knock on
	# the forge's sshd — kept because it tells "still coming up" apart from "down"
	# without having to time a single carrying nc. One carry if a log line bites.
	if nc -z -w2 "$host" "$port" 2>/dev/null; then
		exec nc "$host" "$port"
	fi
	i=$((i + 1))
	if [ "$i" -le "$tries" ]; then sleep "$delay"; fi
done

if tailscale status >/dev/null 2>&1; then
	# "up" per the daemon is not proof the path works — point at a check, not a guess.
	echo "tailnet-proxy: Tailscale says it's up, but $host:$port is unreachable." >&2
	echo "              test the peer:  tailscale ping $host    (if that fails, reconnect: tailscale up)" >&2
else
	echo "tailnet-proxy: Tailscale is off — bring it up, then retry:  tailscale up" >&2
fi
exit 1
