#!/bin/sh
# Sampler behind ~/Library/LaunchAgents/local.vnode-watch.plist. See that file
# for why this exists at all; this one is about what it records.
#
# Two logs, because they answer two different questions and the second is
# expensive to read if it runs at the rate of the first:
#
#   vnode-watch.log          the four counters, every minute — the curve
#   vnode-watch-holders.log  who holds open files, every fifth minute — the name
#
# There is no per-process vnode accounting on macOS: a vnode belongs to the
# kernel's cache, not to whoever caused it. What can be attributed is open files
# and live mappings, which is what pins a vnode so it cannot be recycled — so
# `lsof` counted per pid is the closest thing to "who is doing this", and it
# costs ~0.3s, which is why it can run this often at all.
#
# Root is not needed: mds_stores is the only suspect from #82 that runs as
# _mds_stores. BiomeAgent, corespotlightd and mediaanalysisd all run as the
# logged-in user, so an agent sees them.
#
# Two triggers, because 54h of samples said one was not enough. The free list
# swings between roughly 161k and 243k with the workload and recovers every
# time — a working set, not a leak — and never came within 110k of the absolute
# threshold. Whatever causes the panic therefore eats the whole headroom in a
# burst rather than drifting into it, so an absolute threshold on its own would
# only ever fire once the machine was already dying.
#
# -20000 in a tick is sized off that run: 98% of ticks land within 2500 of no
# change (p1 -2539, p99 +1380) and the largest single drop in 54h was -23354,
# once. Rare enough to mean something, sensitive enough to catch the start.
set -eu

dir=${VNODE_WATCH_DIR:-$HOME/Library/Logs}
low=${VNODE_WATCH_LOW:-50000}
burst=${VNODE_WATCH_BURST:--20000}

set -- $(sysctl -n kern.free_vnodes kern.num_vnodes kern.num_files kern.num_recycledvnodes)
free=$1 num=$2 files=$3 recycled=$4
ts=$(date +%FT%T)

# One tick of state, which is what a burst trigger needs. A gap — sleep, or the
# agent not running — makes the next delta span more than a minute and may fire
# on its own. Rare, and worth a snapshot anyway.
last=$(cat "$dir/.vnode-watch-last" 2>/dev/null) || last=$free
echo "$free" > "$dir/.vnode-watch-last"
delta=$((free - last))

printf '%s free=%s num=%s files=%s recycled=%s delta=%s\n' \
	"$ts" "$free" "$num" "$files" "$recycled" "$delta" >> "$dir/vnode-watch.log"

# Anything but the routine five-minute tick gets the full dump, and says which
# trigger fired: the two mean different things and the log should not flatten
# them into one word.
trigger=schedule
[ "$delta" -gt "$burst" ] || trigger=burst
[ "$free" -ge "$low" ] || trigger=low
if [ "$trigger" = schedule ]; then
	case $(date +%M) in *[05]) ;; *) exit 0 ;; esac
fi

{
	printf '== %s free=%s delta=%s trigger=%s\n' "$ts" "$free" "$delta" "$trigger"

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

	# The half lsof cannot reach: it is unprivileged here, so it sees only this
	# user — and mds_stores, the prime suspect from the 2026-08-12 panic, runs as
	# _mds_stores. top reports page-ins for every process regardless of owner, and
	# page-ins are what separated the two panics in the first place.
	# Cumulative over each process's lifetime, so it is the delta between two
	# snapshots that means something, not the number itself.
	echo '-- pageins (cumulative per process lifetime - read the delta)'
	top -l 1 -stats pid,command,pageins -n 15 -o pageins 2>/dev/null \
		| sed -n '/^PID/,$p'

	[ "$trigger" != schedule ] || exit 0

	# Counts name the process, paths name what it was doing — worth the volume
	# only when something is actually going wrong.
	echo '-- paths'
	lsof -n -P -F n 2>/dev/null | awk '
		/^n\// {
			n = split(substr($0, 2), p, "/"); s = "/" p[2]
			if (n >= 3 && p[3] != "") s = s "/" p[3]
			if (n >= 4 && p[4] != "") s = s "/" p[4]
			print s
		}' | sort | uniq -c | sort -rn | head -15

	# The reason any of this exists: the kernel names the exhausted table while
	# it is happening, and none of it survives the reboot. Copying it out now is
	# the only way #82 ever gets a direct answer instead of an inference.
	# Capped, and the header says so — a vnode storm printed 8890 lines in 40
	# seconds on 2026-08-12, and this may run once a minute while it lasts.
	echo '-- kernel (last 2m, capped at 2000 lines)'
	log show --last 2m --predicate 'process == "kernel"' --style compact 2>/dev/null \
		| head -2000
} >> "$dir/vnode-watch-holders.log"
