#!/usr/bin/env bash
# Self-check for .local/bin/vnode-watch.sh. No framework: sysctl, lsof, top,
# date and log are stubbed onto PATH, so this runs anywhere — including the
# Linux legs of CI, which have none of them — and asserts on the files left
# behind.
#
# The sampler is a daemon, so every case bounds it with VNODE_WATCH_ITERATIONS
# rather than waiting for it to be killed. The sysctl stub walks a scripted
# sequence of free values, one per call, which is what makes a burst reachable
# in a test: the trigger compares against the reading a window ago.
set -eu

script="$(cd "$(dirname "$0")" && pwd)/.local/bin/vnode-watch.sh"
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

mkdir -p "$tmp/bin" "$tmp/logs"
cat > "$tmp/bin/sysctl" <<'STUB'
#!/bin/sh
[ -z "${FAKE_SYSCTL_FAILS:-}" ] || exit 1
n=$(cat "$FAKE_N" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$FAKE_N"
free=$(sed -n "${n}p" "$FAKE_SEQ"); [ -n "$free" ] || free=$(tail -1 "$FAKE_SEQ")
echo "$free"; echo 263168; echo 13500; echo 17000000
STUB
cat > "$tmp/bin/date" <<'STUB'
#!/bin/sh
echo 2026-09-07T12:00:00
STUB
# -F output, which is what the script asks for. The space in the third path is
# the point: the default table format loses everything before it to $NF.
cat > "$tmp/bin/lsof" <<'STUB'
#!/bin/sh
printf 'p738\ncidea\n'
printf 'n/Users/landsman/projects/a/one\n'
printf 'n/Users/landsman/projects/a/two\n'
printf 'n/Users/landsman/Library/Application Support/x\n'
printf 'p718\ncchrome\nn/Applications/Chrome/x\n'
STUB
# A root-owned process on purpose: it is here to cover what lsof cannot see.
cat > "$tmp/bin/top" <<'STUB'
#!/bin/sh
echo "Processes: 900 total"
echo ""
echo "PID  COMMAND        PAGEINS"
echo "936  mediaanalysisd 453379"
echo "548  mds_stores     206348"
STUB
cat > "$tmp/bin/log" <<'STUB'
#!/bin/sh
echo "Timestamp               Ty Process[PID:TID]"
echo "2026-09-07 12:00:00.000 Df kernel[0:1] vnode: table is full"
STUB
chmod +x "$tmp"/bin/*
export PATH="$tmp/bin:$PATH" VNODE_WATCH_DIR="$tmp/logs" VNODE_WATCH_INTERVAL=1
export FAKE_SEQ="$tmp/seq" FAKE_N="$tmp/n"

counters="$tmp/logs/vnode-watch.log"
holders="$tmp/logs/vnode-watch-holders.log"

run() {  # run <iterations> <snapshot-every> <free values...>
	rm -f "$counters" "$holders" "$FAKE_N"
	local iters=$1 snap=$2; shift 2
	printf '%s\n' "$@" > "$FAKE_SEQ"
	VNODE_WATCH_ITERATIONS="$iters" VNODE_WATCH_SNAPSHOT="$snap" "$script"
}

# == ordinary iterations: the curve, and nothing expensive
run 2 99 190000 190000
check "writes one line per iteration" 2 "$(wc -l < "$counters" | tr -d ' ')"
check "with every counter in it" \
	"2026-09-07T12:00:00 free=190000 num=263168 files=13500 recycled=17000000 d60=0" \
	"$(sed -n 1p "$counters")"
check "and no snapshot" "no" "$([ -f "$holders" ] && echo yes || echo no)"

# == the scheduled snapshot
run 2 2 190000 190000
check "snapshots on the scheduled iteration" 1 "$(grep -c '^== ' "$holders")"
check "names the biggest holder first" "3 738 idea" "$(sed -n 3p "$holders")"
check "reaches processes lsof cannot see" 1 "$(grep -c '^548  mds_stores' "$holders")"
check "records the trigger" \
	"== 2026-09-07T12:00:00 free=190000 d60=0 trigger=schedule" "$(sed -n 1p "$holders")"
check "leaves the paths out while nothing is wrong" 0 "$(grep -c '^-- paths' "$holders")"
check "and the kernel log too" 0 "$(grep -c '^-- kernel' "$holders")"
check "but always records page-ins" 1 "$(grep -c '^-- pageins' "$holders")"

# == a burst: still far above the threshold, but the free list fell off a cliff
run 2 99 190000 165000
check "fires on a sudden drop far above the floor" \
	"== 2026-09-07T12:00:00 free=165000 d60=-25000 trigger=burst" "$(sed -n 1p "$holders")"
check "adds the paths, so the count has a subject" 1 \
	"$(grep -c '2 /Users/landsman/projects$' "$holders")"
# With the default table format $NF is "Support/x", which fails the leading
# slash guard and vanishes. This is the regression check for that.
check "counts a path with a space in it" 1 \
	"$(grep -c '1 /Users/landsman/Library$' "$holders")"
check "copies the kernel out before a reboot eats it" 1 \
	"$(grep -c 'vnode: table is full' "$holders")"

# == an ordinary dip is not a burst
run 2 99 190000 185000
check "leaves an ordinary dip alone" "no" "$([ -f "$holders" ] && echo yes || echo no)"

# == below the floor, whatever the slope
run 1 99 40000
check "fires on the floor" \
	"== 2026-09-07T12:00:00 free=40000 d60=0 trigger=low" "$(sed -n 1p "$holders")"

# == the point of the rewrite: sysctl can no longer be run
# This is what ENFILE looks like from inside the loop, and the reason it is a
# daemon — a spawned sampler is simply absent from the log instead.
rm -f "$counters" "$holders" "$FAKE_N"
printf '190000\n' > "$FAKE_SEQ"
FAKE_SYSCTL_FAILS=1 VNODE_WATCH_ITERATIONS=2 VNODE_WATCH_SNAPSHOT=99 "$script"
check "records that it could not sample" 2 "$(grep -c '^SAMPLE-FAILED ' "$counters")"
check "and keeps looping rather than dying" 2 "$(wc -l < "$counters" | tr -d ' ')"
check "dating the marker against its own uptime" 2 \
	"$(grep -c '^SAMPLE-FAILED uptime=[0-9]*s$' "$counters")"

echo
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
