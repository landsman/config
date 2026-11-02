#!/usr/bin/env bash
# Checks the pack lines of omarchy-battery-status --shell against a fake sysfs,
# with upower stubbed. Worth testing because a wrong one is silent: a dead pack
# dropped from the list, or a pack with no power_now shown as drawing nothing.
#
#   bash os/arch/.config/omarchy/plugins/landsman.power/bin/omarchy-battery-status.test.sh

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/omarchy-battery-status"
FAILED=0
t=$(mktemp -d)
trap 'rm -rf "${t:?}"' EXIT

check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else
	echo "FAIL $1"
	echo "       expected: $3"
	echo "       actual:   $2"
	FAILED=1
fi; }

pack() {  # pack <name> <attr=value>...
	local dir=$t/sys/$1 kv
	shift
	mkdir -p "$dir"
	echo Battery >"$dir/type"
	for kv in "$@"; do echo "${kv#*=}" >"$dir/${kv%%=*}"; done
}

mkdir -p "$t/bin"
cat >"$t/bin/upower" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  -e) echo /org/freedesktop/UPower/devices/battery_BAT0 ;;
  *) printf 'state: discharging\nenergy-full: 79.6 Wh\nenergy-rate: 11.9 W\npercentage: 16%%\n' ;;
esac
STUB
chmod +x "$t/bin/upower"

run() { PATH="$t/bin:$PATH" OMARCHY_POWER_SUPPLY_PATH=$t/sys "$SCRIPT" --shell | grep '^pack' | tr '\t' '|'; }

pack BAT0 capacity=46 energy_now=10220000 energy_full=22230000 power_now=11890000 voltage_now=10598000 status=Discharging cycle_count=44
pack BAT1 capacity=5 energy_now=3150000 energy_full=57430000 power_now=0 voltage_now=9484000 'status=Not charging' cycle_count=83
check "lists each battery with its own figures" "$(run)" \
	"pack|BAT0|46|10.2|22.2|11.9|Discharging|44
pack|BAT1|5|3.1|57.4|0.0|Not charging|83"

rm -rf "${t:?}/sys"
pack BAT0 capacity=50 energy_now=1000000 energy_full=2000000 current_now=-1000000 voltage_now=10000000 status=Discharging cycle_count=-1
check "works the draw out from current and voltage, and drops a cycle count of -1" "$(run)" \
	"pack|BAT0|50|1.0|2.0|10.0|Discharging|"

pack BAT1 capacity=0 energy_now=0 energy_full=57430000 voltage_now=0 status=Unknown cycle_count=-1
check "lists a dead pack after the live one" "$(run | tail -n 1)" \
	"pack|BAT1|0|0.0|57.4||Unknown|"

exit "$FAILED"
