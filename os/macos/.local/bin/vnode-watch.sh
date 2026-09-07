#!/bin/sh
# Sampler behind ~/Library/LaunchAgents/local.vnode-watch.plist. See that file
# for why this exists at all; this one is about what it records.
#
#   vnode-watch.log          the four counters, every 5s — the curve
#   vnode-watch-holders.log  who holds open files, every 5 min — the name
#
# It runs as one long-lived process rather than a job launchd spawns on a timer,
# and that is the whole point rather than a detail. On 2026-09-07 the panic was
# preceded by this in launchd's own log:
#
#   trampoline spawn failed: 23: Too many open files in system
#   Could not spawn process /usr/libexec/xpcproxy: 23
#
# The sampler was a StartInterval job, so every sample needed launchd to fork it
# — which is the first operation ENFILE breaks. The last reading was 73 seconds
# before the panic and showed a healthy 184085 free. Instrumentation that has to
# be spawned cannot observe the thing that stops spawning.
#
# So: nothing is exec'd per iteration. The log fd is opened once, `printf` and
# `read` are shell builtins, and the wait is `read -t` against a fifo nobody
# writes to rather than /bin/sleep. When `sysctl` can no longer be exec'd the
# loop notices and writes SAMPLE-FAILED with $SECONDS — which is the timestamp
# of the collapse, recorded from inside it.
#
# There is no per-process vnode accounting on macOS: a vnode belongs to the
# kernel's cache, not to whoever caused it. What can be attributed is open files
# and live mappings, which is what pins a vnode against recycling — so `lsof`
# per pid is the closest thing to "who is doing this". It needs no root:
# mds_stores is the only suspect from #82 not owned by the logged-in user, and
# `top` covers page-ins for that one.
#
# The burst trigger is measured over 60s and not over one 5s sample, so the
# sizing stays the one the data supports: across 54h of minute samples, 98%
# landed within 2500 of no change (p1 -2539, p99 +1380) and the largest single
# drop was -23354, once. Comparing against the reading from twelve iterations
# back keeps that threshold meaningful at the finer sample rate.
#
# ponytail: the 60s window lives in memory, so a restart is blind for its first
# minute. Persisting it would buy one minute after an event that reboots the
# machine anyway.
set -u

dir=${VNODE_WATCH_DIR:-$HOME/Library/Logs}
low=${VNODE_WATCH_LOW:-50000}
burst=${VNODE_WATCH_BURST:--20000}
every=${VNODE_WATCH_INTERVAL:-5}
snap_every=${VNODE_WATCH_SNAPSHOT:-60}     # iterations between snapshots: 60 x 5s
max_iter=${VNODE_WATCH_ITERATIONS:-0}      # 0 = forever; the test bounds it

# Opened once. A write to an open fd needs no file table entry, so the marker
# below can still be recorded when opening anything would fail.
exec 3>> "$dir/vnode-watch.log"

# The wait, without /bin/sleep. Opening the fifo read-write means it never sees
# EOF, so `read -t` blocks for the timeout and returns non-zero — which is the
# expected path, not an error.
fifo=$dir/.vnode-watch-tick
[ -p "$fifo" ] || { rm -f "$fifo"; mkfifo "$fifo" 2>/dev/null; }
if exec 9<> "$fifo" 2>/dev/null; then wait_builtin=1; else wait_builtin=0; fi

tick() {
	if [ "$wait_builtin" = 1 ]; then
		read -t "$every" -u 9 _ 2>/dev/null || true
	else
		sleep "$every"
	fi
}

[ "$every" -ge 1 ] || every=1
win=$((60 / every + 1))

window=
n=0
while :; do
	n=$((n + 1))

	vals=$(sysctl -n kern.free_vnodes kern.num_vnodes kern.num_files kern.num_recycledvnodes 2>/dev/null) || vals=
	if [ -z "$vals" ]; then
		# sysctl could not be run. Under ENFILE that is the finding, not a
		# failure to report: $SECONDS dates it against the first line above.
		printf 'SAMPLE-FAILED uptime=%ss\n' "$SECONDS" >&3
		[ "$max_iter" -eq 0 ] || [ "$n" -lt "$max_iter" ] || break
		tick; continue
	fi

	set -- $vals
	free=$1 num=$2 files=$3 recycled=$4
	ts=$(date +%FT%T 2>/dev/null) || ts=+${SECONDS}s

	# Twelve samples back at the default rate, so the threshold keeps the
	# meaning it was measured with.
	window="$window $free"
	set -- $window
	while [ $# -gt "$win" ]; do shift; done
	window="$*"
	d60=$((free - $1))

	printf '%s free=%s num=%s files=%s recycled=%s d60=%s\n' \
		"$ts" "$free" "$num" "$files" "$recycled" "$d60" >&3

	trigger=schedule
	[ "$d60" -gt "$burst" ] || trigger=burst
	[ "$free" -ge "$low" ] || trigger=low
	if [ "$trigger" = schedule ] && [ $((n % snap_every)) -ne 0 ]; then
		[ "$max_iter" -eq 0 ] || [ "$n" -lt "$max_iter" ] || break
		tick; continue
	fi

	{
		printf '== %s free=%s d60=%s trigger=%s\n' "$ts" "$free" "$d60" "$trigger"

		# -F rather than the default table: a NAME with a space in it — every
		# "Application Support/..." there is — loses its front half to $NF, and
		# that is exactly where an app's own churn lives.
		echo '-- holders (open files: count pid command)'
		lsof -n -P -F pcn 2>/dev/null | awk '
			/^p/ { pid = substr($0, 2); next }
			/^c/ { cmd = substr($0, 2); next }
			/^n/ { c[pid " " cmd]++ }
			END  { for (k in c) print c[k], k }' \
			| sort -rn | head -25

		# The half lsof cannot reach: it is unprivileged, so it sees only this
		# user. top reports page-ins for every process whatever its owner, and
		# page-ins are what separated the first two panics.
		echo '-- pageins (cumulative per process lifetime - read the delta)'
		top -l 1 -stats pid,command,pageins -n 15 -o pageins 2>/dev/null \
			| sed -n '/^PID/,$p'

		# An `exit` here would end the daemon rather than the snapshot, which
		# is why this is an if and not the early return it used to be.
		if [ "$trigger" != schedule ]; then
			echo '-- paths'
			lsof -n -P -F n 2>/dev/null | awk '
				/^n\// {
					n = split(substr($0, 2), p, "/"); s = "/" p[2]
					if (n >= 3 && p[3] != "") s = s "/" p[3]
					if (n >= 4 && p[4] != "") s = s "/" p[4]
					print s
				}' | sort | uniq -c | sort -rn | head -15

			# The kernel names the exhausted table while it happens and none of
			# it survives the reboot. Capped, and the header says so: a vnode
			# storm printed 8890 lines in 40 seconds on 2026-08-12.
			echo '-- kernel (last 2m, capped at 2000 lines)'
			log show --last 2m --predicate 'process == "kernel"' --style compact 2>/dev/null \
				| head -2000
		fi
	} >> "$dir/vnode-watch-holders.log"

	[ "$max_iter" -eq 0 ] || [ "$n" -lt "$max_iter" ] || break
	tick
done
