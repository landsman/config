#!/usr/bin/env bash
# Self-check for .local/bin/vnode-watch.sh, the sampler behind
# https://github.com/landsman/config/issues/82
# No framework: sysctl, lsof, top,
# date, log and sleep are stubbed onto PATH, so this runs anywhere — including
# the Linux legs of CI — and asserts on the files left behind.
#
# The script is #!/bin/sh, which is bash on macOS and dash on Linux, and it
# behaves differently on purpose: `read -t` is a bash extension, so only one of
# them gets the exec-free wait. The suite therefore reads the mode out of the
# STARTED line and asserts against that, rather than assuming a platform.
#
# Two of these checks exist because an earlier version passed sixteen assertions
# while not waiting at all: nothing measured elapsed time, and nothing noticed
# that the wait had been replaced by exec'ing /bin/sleep. Output-only assertions
# cannot see the property this daemon is built around.
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
n=$(cat "$FAKE_N" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$FAKE_N"
free=$(sed -n "${n}p" "$FAKE_SEQ"); [ -n "$free" ] || free=$(tail -1 "$FAKE_SEQ")
case ${FAKE_MODE:-ok} in
	short)      echo "$free"; echo 263168; echo 13500; exit 1 ;;   # one oid gone
	nonnumeric) echo nan; echo 263168; echo 13500; echo 17000000 ;;
	dead)       exit 1 ;;
	*)          echo "$free"; echo 263168; echo 13500; echo 17000000 ;;
esac
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
echo "Processes: 900 total"; echo ""
echo "PID  COMMAND        PAGEINS"
echo "936  mediaanalysisd 453379"
echo "548  mds_stores     206348"
STUB
cat > "$tmp/bin/log" <<'STUB'
#!/bin/sh
echo "Timestamp               Ty Process[PID:TID]"
echo "2026-09-07 12:00:00.000 Df kernel[0:1] vnode: table is full"
STUB
cat > "$tmp/bin/fs_usage" <<'STUB'
#!/bin/sh
echo "12:00:00  open      F=3   (R___)  /some/path   0.000018   somebody"
STUB
# Records that it ran, so "the wait is exec-free" is checkable rather than assumed.
cat > "$tmp/bin/sleep" <<'STUB'
#!/bin/sh
echo "$@" >> "$FAKE_SLEEPS"
exec /bin/sleep "$@"
STUB
chmod +x "$tmp"/bin/*
export PATH="$tmp/bin:$PATH" VNODE_WATCH_DIR="$tmp/logs" VNODE_WATCH_INTERVAL=1
export FAKE_SEQ="$tmp/seq" FAKE_N="$tmp/n" FAKE_SLEEPS="$tmp/sleeps"

counters="$tmp/logs/vnode-watch.log"
fsusage="$tmp/logs/vnode-watch-fsusage.log"
holders="$tmp/logs/vnode-watch-holders.log"
errlog="$tmp/logs/vnode-watch.err"

run() {  # run <iterations> <snapshot-every> <free values...>
	rm -f "$counters" "$holders" "$errlog" "$fsusage" "$FAKE_N" "$FAKE_SLEEPS"
	local iters=$1 snap=$2; shift 2
	printf '%s\n' "$@" > "$FAKE_SEQ"
	VNODE_WATCH_ITERATIONS="$iters" VNODE_WATCH_SNAPSHOT="$snap" "$script"
	wait 2>/dev/null || true          # snapshots are backgrounded
}
samples() { grep -cE '^[^ ]+ free=' "$counters"; }

# == it announces how it is configured, including which wait it got
run 1 99 190000
check "records its configuration" 1 \
	"$(grep -c '^[^ ]* STARTED interval=1s wait=\(builtin\|sleep\) win=61 cooldown=12$' "$counters")"
mode=$(sed -n 's/.*wait=\([a-z]*\).*/\1/p' "$counters" | head -1)
echo "     (wait mode here: $mode)"

# == ordinary iterations
run 2 99 190000 190000
check "writes one line per iteration" 2 "$(samples)"
check "with every counter in it" \
	"2026-09-07T12:00:00 free=190000 num=263168 files=13500 recycled=17000000 d60=0" \
	"$(sed -n 2p "$counters")"
check "and no snapshot" "no" "$([ -f "$holders" ] && echo yes || echo no)"
check "and nothing on stderr" 0 "$(wc -l < "$errlog" | tr -d ' ')"

# == it actually waits, and in builtin mode without exec'ing anything
# An earlier version passed every other check in this file while not waiting.
start=$SECONDS
run 3 99 190000 190000 190000
elapsed=$((SECONDS - start))
check "waits between iterations" "yes" "$([ "$elapsed" -ge 2 ] && echo yes || echo no)"
if [ "$mode" = builtin ]; then
	check "without exec'ing /bin/sleep" "no" "$([ -s "$FAKE_SLEEPS" ] && echo yes || echo no)"
else
	check "falling back to sleep, as the STARTED line says" "yes" \
		"$([ -s "$FAKE_SLEEPS" ] && echo yes || echo no)"
fi

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

# == a burst, and it fires on the first one rather than after a cooldown
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

# == a held trigger must not snapshot every tick
# Six samples under the floor: two full lsof scans per tick, against the very
# table that is running out, is the instrument making the incident worse.
VNODE_WATCH_COOLDOWN=3 run 6 99 40000 40000 40000 40000 40000 40000
check "throttles a sustained trigger" 2 "$(grep -c '^== ' "$holders")"
check "while still sampling every tick" 6 "$(samples)"

# == an ordinary dip is not a burst
run 2 99 190000 185000
check "leaves an ordinary dip alone" "no" "$([ -f "$holders" ] && echo yes || echo no)"

# == the window slides, which weeks of uptime depend on
VNODE_WATCH_INTERVAL=30 run 4 99 100000 99000 98000 97000
check "compares against the far end of the window, not the previous sample" \
	"-2000" "$(sed -n '$p' "$counters" | sed 's/.*d60=//')"

# == sysctl half-answers after an OS upgrade renames an oid
# It exits non-zero while printing the values it does know, so trusting the
# status would make every sample look like the ENFILE marker forever.
FAKE_MODE=short run 2 99 190000 190000
check "does not mistake a renamed oid for the thing it watches for" 2 \
	"$(grep -c '^SAMPLE-FAILED iter=[0-9]* values=3$' "$counters")"
check "and stays alive through it" 0 "$(samples)"

# == a non-numeric reading must not be fatal arithmetic
FAKE_MODE=nonnumeric run 2 99 190000 190000
check "survives a non-numeric reading" 2 "$(grep -c '^SAMPLE-BAD iter=[0-9]*$' "$counters")"

# == and the case it is all for: sysctl cannot be run at all
FAKE_MODE=dead run 2 99 190000
check "records that it could not sample" 2 \
	"$(grep -c '^SAMPLE-FAILED iter=[0-9]* values=0$' "$counters")"
check "and keeps counting iterations rather than dying on the first" 1 \
	"$(grep -c '^SAMPLE-FAILED iter=2 ' "$counters")"

# == fs_usage: off unless asked for, and only for a real trigger
# It is the only thing that measures open() rate per process, which is what the
# 2026-09-08 capture showed this is — and it needs root, so the agent leaves it
# off and the daemon plist turns it on.
run 1 99 40000
check "no trace unless it is asked for" "no" "$([ -f "$fsusage" ] && echo yes || echo no)"

VNODE_WATCH_TRACE=10 run 1 99 40000
check "traces a trigger when asked" 1 "$(grep -c '^== .*trigger=low ' "$fsusage")"
check "and captures what fs_usage said" 1 "$(grep -c 'open  ' "$fsusage")"

VNODE_WATCH_TRACE=10 run 2 2 190000 190000
check "does not trace a routine snapshot" "no" "$([ -f "$fsusage" ] && echo yes || echo no)"

# A trigger that holds must not start a trace per snapshot: fs_usage is a
# firehose and several of them at once would be the instrument making it worse.
VNODE_WATCH_TRACE=10 VNODE_WATCH_COOLDOWN=1 run 3 99 40000 40000 40000
check "starts one trace, not one per snapshot" 1 "$(grep -c '^== ' "$fsusage")"

echo
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
