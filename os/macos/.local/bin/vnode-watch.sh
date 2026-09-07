#!/bin/sh
# Sampler behind ~/Library/LaunchAgents/local.vnode-watch.plist. See that file
# for why this exists at all; this one is about what it records.
#
#   vnode-watch.log          the counters, every 5s — the curve
#   vnode-watch-holders.log  who holds open files, throttled — the name
#   vnode-watch.err          stderr, because a daemon whose failure mode is
#                            silence must not send its diagnostics to /dev/null
#
# It runs as one long-lived process rather than a job launchd spawns on a timer.
# On 2026-09-07 launchd logged this for the previous version, seconds before the
# panic:
#
#   trampoline spawn failed: 23: Too many open files in system
#
# A sampler launchd has to fork cannot observe the thing that stops forking, and
# the last reading was 73s before the panic showing a healthy 184085 free.
#
# The honest claim about this one, since the first draft overstated it: the
# *write* and the *wait* need no exec, so a sample that cannot be taken is still
# recorded. The sample itself execs `sysctl`, and the timestamp execs `date` —
# both fail under ENFILE, and that failure is the finding rather than an outage.
# `$( )` also allocates a pipe before forking, so the substitution fails before
# sysctl is even reached; the marker below is what that looks like.
#
# What must stay true on the hot path: no redirection. A `2>/dev/null` needs a
# file table entry, which is the exhausted resource — the earlier version had
# one inside the wait, so under ENFILE the wait returned instantly and the loop
# would have spun at CPU speed writing markers. Redirection is allowed on the
# snapshot path, which execs `lsof` and `top` anyway.
#
# There is no per-process vnode accounting on macOS: a vnode belongs to the
# kernel's cache, not to whoever caused it. What can be attributed is open files
# and live mappings, which is what pins a vnode against recycling. It needs no
# root — mds_stores is the only suspect from #82 not owned by the logged-in
# user, and `top` covers page-ins for that one.
#
# The snapshot runs in the background and is throttled. Both are load-bearing: it
# costs seconds on an idle machine and far more under pressure, so running it
# inline blinds the sampler exactly when the curve matters, and running it every
# tick while a trigger holds means two full `lsof` scans every 5s — against the
# file table that is the resource running out.
#
# The burst threshold is measured over a window of samples rather than one, so
# the sizing stays the one the data supports: across 54h, 98% of minute-to-minute
# readings landed within 2500 of no change (p1 -2539, p99 +1380) and the largest
# single drop was -23354, once.
#
# ponytail: the window lives in memory, so a restart is blind for its first
# minute, and the logs are append-only with no rotation. The throttle bounds the
# worst case to one snapshot a minute; a vnode storm can still put ~250 KB in
# each. Rotate if a run ever fills anything.
set -u

dir=${VNODE_WATCH_DIR:-$HOME/Library/Logs}
low=${VNODE_WATCH_LOW:-50000}
burst=${VNODE_WATCH_BURST:--20000}
every=${VNODE_WATCH_INTERVAL:-5}
snap_every=${VNODE_WATCH_SNAPSHOT:-60}     # iterations between scheduled snapshots
cooldown=${VNODE_WATCH_COOLDOWN:-12}       # minimum iterations between triggered ones
max_iter=${VNODE_WATCH_ITERATIONS:-0}      # 0 = forever; the test bounds it

[ "$every" -ge 1 ] || every=1
[ "$snap_every" -ge 1 ] || snap_every=1
win=$((60 / every + 1))
[ "$win" -ge 2 ] || win=2

mkdir -p "$dir" 2>/dev/null || true
exec 2>> "$dir/vnode-watch.err"
exec 3>> "$dir/vnode-watch.log"

# The wait, without /bin/sleep. Opening the fifo read-write means it never sees
# EOF, so `read -t` blocks for the timeout and returns non-zero — the expected
# path, not an error. `read -t` is a bash extension and /bin/sh is dash on
# Linux, so the mode is decided by BASH_VERSION rather than by trying it, and
# it is recorded below: a daemon that silently fell back to exec'ing sleep would
# look healthy while being the thing this rewrite exists to stop being.
fifo=$dir/.vnode-watch-tick
wait_mode=sleep
if [ -n "${BASH_VERSION:-}" ]; then
	[ -p "$fifo" ] || { rm -f "$fifo"; mkfifo "$fifo" 2>/dev/null || true; }
	if [ -p "$fifo" ]; then
		exec 9<> "$fifo"
		wait_mode=builtin
	fi
fi

tick() {
	if [ "$wait_mode" = builtin ]; then
		read -t "$every" -u 9 _ || true
	else
		sleep "$every" || true
	fi
}

snapshot() {  # snapshot <ts> <free> <d60> <trigger>
	printf '== %s free=%s d60=%s trigger=%s\n' "$1" "$2" "$3" "$4"

	# -F rather than the default table: a NAME with a space in it — every
	# "Application Support/..." there is — loses its front half to $NF, and that
	# is exactly where an app's own churn lives.
	echo '-- holders (open files: count pid command)'
	lsof -n -P -F pcn 2>/dev/null | awk '
		/^p/ { pid = substr($0, 2); next }
		/^c/ { cmd = substr($0, 2); next }
		/^n/ { c[pid " " cmd]++ }
		END  { for (k in c) print c[k], k }' \
		| sort -rn | head -25

	# The half lsof cannot reach: it is unprivileged, so it sees only this user.
	# top reports page-ins for every process whatever its owner, and page-ins are
	# what separated the first two panics.
	echo '-- pageins (cumulative per process lifetime - read the delta)'
	top -l 1 -stats pid,command,pageins -n 15 -o pageins 2>/dev/null \
		| sed -n '/^PID/,$p'

	[ "$4" != schedule ] || return 0

	echo '-- paths'
	lsof -n -P -F n 2>/dev/null | awk '
		/^n\// {
			n = split(substr($0, 2), p, "/"); s = "/" p[2]
			if (n >= 3 && p[3] != "") s = s "/" p[3]
			if (n >= 4 && p[4] != "") s = s "/" p[4]
			print s
		}' | sort | uniq -c | sort -rn | head -15

	# The kernel names the exhausted table while it happens and none of it
	# survives the reboot. Capped, and the header says so: a vnode storm printed
	# 8890 lines in 40 seconds on 2026-08-12.
	echo '-- kernel (last 2m, capped at 2000 lines)'
	log show --last 2m --predicate 'process == "kernel"' --style compact 2>/dev/null \
		| head -2000
}

started=$(date +%FT%T 2>/dev/null) || started=unknown
printf '%s STARTED interval=%ss wait=%s win=%s cooldown=%s\n' \
	"$started" "$every" "$wait_mode" "$win" "$cooldown" >&3

window=
n=0
# One cooldown in the past, so the first trigger after startup fires at once
# instead of waiting out a window it never had.
last_snap=$((0 - cooldown))
snap_pid=0
while :; do
	n=$((n + 1))

	# No 2>/dev/null: that redirect is a file table entry, and this is the hot
	# path. sysctl's own complaints go to the err log instead.
	vals=$(sysctl -n kern.free_vnodes kern.num_vnodes kern.num_files kern.num_recycledvnodes)
	set -- $vals

	# Judged on what came back, not on the exit status. sysctl exits non-zero
	# when any one oid is unknown while still printing the others, so trusting
	# the status would throw away three good values — and turn a renamed oid
	# after an OS upgrade into a permanent SAMPLE-FAILED that reads exactly like
	# the ENFILE it is supposed to mean.
	ok=yes
	[ $# -ge 4 ] || ok=short
	# Only safe to look at $4 once the count is known: under set -u an unset
	# positional is fatal, and a dying daemon is an invisible respawn loop.
	[ "$ok" != yes ] || case "$1$2$3$4" in ''|*[!0-9]*) ok=nonnumeric ;; esac

	if [ "$ok" = short ]; then
		printf 'SAMPLE-FAILED iter=%s values=%s\n' "$n" "$#" >&3
	elif [ "$ok" = nonnumeric ]; then
		printf 'SAMPLE-BAD iter=%s\n' "$n" >&3
	else
		free=$1 num=$2 files=$3 recycled=$4
		ts=$(date +%FT%T) || ts=
		[ -n "$ts" ] || ts=iter-$n

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

		due=0
		[ $((n % snap_every)) -ne 0 ] || due=1
		if [ "$trigger" != schedule ] && [ $((n - last_snap)) -ge "$cooldown" ]; then
			due=1
		fi

		# Backgrounded so a snapshot cannot blind the sampler, and skipped
		# outright while the previous one is still going: under pressure these
		# take longer than the interval, and piling them up would have the
		# instrument competing for the resource it is measuring.
		if [ "$due" -eq 1 ] && { [ "$snap_pid" -eq 0 ] || ! kill -0 "$snap_pid" 2>/dev/null; }; then
			last_snap=$n
			snapshot "$ts" "$free" "$d60" "$trigger" \
				>> "$dir/vnode-watch-holders.log" 2>/dev/null &
			snap_pid=$!
		fi
	fi

	[ "$max_iter" -eq 0 ] || [ "$n" -lt "$max_iter" ] || break
	tick
done

# Only reached when bounded. A backgrounded snapshot outlives the loop, so
# without this the last one is half-written when the process goes away.
[ "$snap_pid" -eq 0 ] || wait "$snap_pid" 2>/dev/null || true
