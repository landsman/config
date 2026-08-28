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
# ponytail: threshold on the free count, no rate-of-change trigger. A collapse
# faster than one tick would be caught on the next one anyway — the ENFILE storm
# on 2026-08-26 lasted two minutes. Add a delta trigger if a run turns out to
# miss the window.
set -eu

dir=${VNODE_WATCH_DIR:-$HOME/Library/Logs}
low=${VNODE_WATCH_LOW:-50000}

set -- $(sysctl -n kern.free_vnodes kern.num_vnodes kern.num_files kern.num_recycledvnodes)
free=$1 num=$2 files=$3 recycled=$4
ts=$(date +%FT%T)

printf '%s free=%s num=%s files=%s recycled=%s\n' \
	"$ts" "$free" "$num" "$files" "$recycled" >> "$dir/vnode-watch.log"

# Below the threshold every tick is worth a snapshot, and the paths come with
# it. Above it, every fifth minute is plenty for a run-up that takes days.
crisis=0
[ "$free" -lt "$low" ] && crisis=1 || true
case $(date +%M) in *[05]) due=1 ;; *) due=$crisis ;; esac
[ "$due" -eq 1 ] || exit 0

{
	printf '== %s free=%s crisis=%s\n' "$ts" "$free" "$crisis"
	# -F rather than the default table: a NAME with a space in it — every
	# "Application Support/..." there is — loses its front half to $NF, and that
	# is exactly where an app's own churn lives.
	lsof -n -P -F pcn 2>/dev/null | awk '
		/^p/ { pid = substr($0, 2); next }
		/^c/ { cmd = substr($0, 2); next }
		/^n/ { c[pid " " cmd]++ }
		END  { for (k in c) print c[k], k }' \
		| sort -rn | head -25
	# Counts name the process, paths name what it was doing — worth the volume
	# only when something is actually going wrong.
	[ "$crisis" -eq 0 ] || lsof -n -P -F n 2>/dev/null | awk '
		/^n\// {
			n = split(substr($0, 2), p, "/"); s = "/" p[2]
			if (n >= 3 && p[3] != "") s = s "/" p[3]
			if (n >= 4 && p[4] != "") s = s "/" p[4]
			print s
		}' | sort | uniq -c | sort -rn | head -15
} >> "$dir/vnode-watch-holders.log"
