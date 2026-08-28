#!/usr/bin/env bash
# Self-check for .local/bin/vnode-watch.sh. No framework: sysctl, lsof and date
# are stubbed onto PATH, so this runs anywhere — including the Linux legs of
# CI, which have none of the three — and asserts on the files left behind.
#
# date is stubbed too, not just the two data sources: the every-fifth-minute
# branch reads the wall clock, and a test that waits for the right minute is a
# test nobody runs.
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
echo "${FAKE_FREE:-190000}"; echo 263168; echo 13500; echo 17000000
STUB
cat > "$tmp/bin/date" <<'STUB'
#!/bin/sh
case "$1" in
	+%M) echo "${FAKE_MIN:-07}" ;;
	*)   echo 2026-08-28T12:00:00 ;;
esac
STUB
# -F output, which is what the script asks for. The space in the third path is
# the point: the default table format loses everything before it to $NF.
cat > "$tmp/bin/lsof" <<'STUB'
#!/bin/sh
printf 'p738\ncidea\n'
printf 'n/Users/landsman/projects/a/one\n'
printf 'n/Users/landsman/projects/a/two\n'
printf 'n/Users/landsman/Library/Application Support/x\n'
printf 'p718\ncchrome\n'
printf 'n/Applications/Chrome/x\n'
STUB
# top is stubbed with a root-owned process in it on purpose: it is there to
# cover exactly what lsof cannot see without privileges.
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
echo "2026-08-28 12:00:00.000 Df kernel[0:1] vnode: table is full"
STUB
chmod +x "$tmp/bin/sysctl" "$tmp/bin/date" "$tmp/bin/lsof" "$tmp/bin/top" "$tmp/bin/log"
export PATH="$tmp/bin:$PATH" VNODE_WATCH_DIR="$tmp/logs"

counters="$tmp/logs/vnode-watch.log"
holders="$tmp/logs/vnode-watch-holders.log"

# == an ordinary tick: the curve, and nothing expensive
FAKE_MIN=07 "$script"
check "writes one counters line" 1 "$(wc -l < "$counters" | tr -d ' ')"
check "with every counter in it" \
	"2026-08-28T12:00:00 free=190000 num=263168 files=13500 recycled=17000000" \
	"$(cat "$counters")"
check "and no snapshot" "no" "$([ -f "$holders" ] && echo yes || echo no)"

# == appends, because a truncating sampler loses the run-up it exists to show
FAKE_MIN=07 "$script"
check "appends rather than truncates" 2 "$(wc -l < "$counters" | tr -d ' ')"

# == every fifth minute: who holds what
FAKE_MIN=15 "$script"
check "snapshots on the fifth minute" "yes" "$([ -f "$holders" ] && echo yes || echo no)"
check "names the biggest holder first" "3 738 idea" "$(sed -n 3p "$holders")"
check "reaches processes lsof cannot see" 1 "$(grep -c '^548  mds_stores' "$holders")"
check "records the free count beside it" \
	"== 2026-08-28T12:00:00 free=190000 crisis=0" "$(sed -n 1p "$holders")"
check "leaves the paths out while nothing is wrong" 0 "$(grep -c '^-- paths' "$holders")"
check "and leaves the kernel log alone too" 0 "$(grep -c '^-- kernel' "$holders")"
check "but always records page-ins" 1 "$(grep -c '^-- pageins' "$holders")"

# == below the threshold: every tick, and the paths too
rm -f "$holders"
FAKE_MIN=07 FAKE_FREE=40000 "$script"
check "snapshots off-schedule when the free list is low" "yes" \
	"$([ -f "$holders" ] && echo yes || echo no)"
check "says which side of the threshold it is on" \
	"== 2026-08-28T12:00:00 free=40000 crisis=1" "$(sed -n 1p "$holders")"
check "adds the paths, so the count has a subject" 1 \
	"$(grep -c '2 /Users/landsman/projects$' "$holders")"
# The regression this format exists to prevent: with the default table format
# $NF is "Support/x", which fails the leading-slash guard and vanishes.
check "counts a path with a space in it" 1 \
	"$(grep -c '1 /Users/landsman/Library$' "$holders")"
# The whole reason for the agent: this line does not survive the reboot, so it
# has to be copied out while the machine is still up.
check "copies the kernel out before the reboot eats it" 1 \
	"$(grep -c 'vnode: table is full' "$holders")"

# == the threshold is a threshold, not a constant
rm -f "$holders"
FAKE_MIN=07 FAKE_FREE=40000 VNODE_WATCH_LOW=1000 "$script"
check "a lower threshold stops it firing" "no" \
	"$([ -f "$holders" ] && echo yes || echo no)"

echo
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
