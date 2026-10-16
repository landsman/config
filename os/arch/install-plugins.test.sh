#!/usr/bin/env bash
# Checks install-plugins.sh without Omarchy: `omarchy` is a stub on PATH that
# logs what it is asked and keeps enabled/disabled state in a file, and the
# plugin comes from a throwaway git repo instead of GitHub.
#
# The cases that matter are the re-runs. The script is meant to be run again
# and again — to bump a pin, or after a reinstall — so a second run that
# re-patches, re-enables or restarts the shell for nothing is a failure, and so
# is a bump that throws away a local change it did not make.
#
#   bash os/arch/install-plugins.test.sh

# The stub is written to disk verbatim, so the unexpanded $1/$@ in it are the
# point, not an oversight.
# shellcheck disable=SC2016
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT=$HERE/install-plugins.sh
FAILED=0
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

ok() { echo "ok   $1"; }
fail() { echo "FAIL $1"; FAILED=1; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else
	fail "$1"
	echo "       expected: $3"
	echo "       actual:   $2"
fi; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }

# == fixtures: an upstream with one commit, and a patch made against it
UP=$ROOT/upstream
mkdir -p "$UP"
g -C "$UP" init -q
printf '{ "id": "t.pulse" }\n' >"$UP/manifest.json"
printf 'labelText: parts.join(" ")\n' >"$UP/BarWidget.qml"
g -C "$UP" add -A && g -C "$UP" commit -qm one
C1=$(g -C "$UP" rev-parse HEAD)

mkdir -p "$ROOT/patches"
sed -i.orig 's/join(" ")/join(separator)/' "$UP/BarWidget.qml" && rm "$UP/BarWidget.qml.orig"
{ echo "a description line, which git apply skips"; echo; g -C "$UP" diff; } >"$ROOT/patches/t.pulse.patch"
g -C "$UP" checkout -q -- BarWidget.qml

mkdir -p "$ROOT/bin"
cat >"$ROOT/bin/omarchy" <<'STUB'
#!/usr/bin/env bash
echo "omarchy $*" >>"$LOG"
case "$1 $2" in
	"plugin add")      git clone -q "$UPSTREAM" "$PLUGINS_DIR/t.pulse" ;;
	"plugin list")     jq -R '{id: ., enabled: true}' <"$ENABLED" | jq -s . ;;
	"plugin enable")   echo "$3" >>"$ENABLED" ;;
	"plugin disable")  grep -vx "$3" "$ENABLED" >"$ENABLED.tmp"; mv "$ENABLED.tmp" "$ENABLED" ;;
esac
exit 0
STUB
chmod +x "$ROOT/bin/omarchy"

export PATH="$ROOT/bin:$PATH" LOG=$ROOT/log ENABLED=$ROOT/enabled UPSTREAM=$UP
export PLUGINS_DIR=$ROOT/plugins PATCHES_DIR=$ROOT/patches SHELL_CONFIG=$ROOT/shell.json
mkdir -p "$PLUGINS_DIR"
: >"$ENABLED"
echo '{"bar":{"layout":{"right":[{"id":"t.pulse"}]}}}' >"$SHELL_CONFIG"
DIR=$PLUGINS_DIR/t.pulse

# run <function call...> — in a subshell, as the script's own `set -e` would
# otherwise end this test at the first expected failure. Prints CHANGED last.
run() { : >"$LOG"; ( . "$SCRIPT"; "$@" && echo "changed=$CHANGED" ); }

# == git_plugin
out=$(run git_plugin t.pulse "$UP" "$C1")
check "adds a missing plugin" "$(grep -c 'omarchy plugin add' "$LOG")" "1"
check "pins it to the commit" "$(git -C "$DIR" rev-parse HEAD)" "$C1"
check "applies its patch" "$(cat "$DIR/BarWidget.qml")" 'labelText: parts.join(separator)'
check "reports the change" "${out##*$'\n'}" "changed=1"

out=$(run git_plugin t.pulse "$UP" "$C1")
check "a re-run changes nothing" "${out##*$'\n'}" "changed=0"
check "a re-run calls nothing" "$(cat "$LOG")" ""
check "a re-run does not patch twice" "$(cat "$DIR/BarWidget.qml")" 'labelText: parts.join(separator)'

echo "more" >>"$UP/manifest.json"
g -C "$UP" commit -qam two
C2=$(g -C "$UP" rev-parse HEAD)
out=$(run git_plugin t.pulse "$UP" "$C2")
check "a bumped pin fetches and moves" "$(git -C "$DIR" rev-parse HEAD)" "$C2"
check "the patch survives the bump" "$(cat "$DIR/BarWidget.qml")" 'labelText: parts.join(separator)'
check "a bump is a change" "${out##*$'\n'}" "changed=1"

echo "mine" >>"$DIR/manifest.json"
run git_plugin t.pulse "$UP" "$C1" >/dev/null 2>&1
check "a bump refuses a local change that is not the patch" "$?" "1"
check "and leaves that change where it was" "$(tail -1 "$DIR/manifest.json")" "mine"
check "and leaves the commit where it was" "$(git -C "$DIR" rev-parse HEAD)" "$C2"
git -C "$DIR" checkout -q -- manifest.json

# == enable / disable
out=$(run enable t.pulse --after omarchy.tray)
check "enables with the placement" "$(cat "$LOG")" "omarchy plugin list --json
omarchy plugin enable t.pulse --after omarchy.tray"
out=$(run enable t.pulse --after omarchy.tray)
check "does not enable twice, so a moved widget stays moved" "${out##*$'\n'}" "changed=0"
out=$(run disable other.power)
check "disabling an already disabled plugin changes nothing" "${out##*$'\n'}" "changed=0"
out=$(run disable t.pulse)
check "disables an enabled one" "$(grep -c 'plugin disable t.pulse' "$LOG")" "1"

# == setting
out=$(run setting t.pulse separator ' · ')
check "sets a value that differs" "$(tail -1 "$LOG")" "omarchy bar set t.pulse separator  · "
echo '{"bar":{"layout":{"right":[{"id":"t.pulse","separator":" · "}]}}}' >"$SHELL_CONFIG"
out=$(run setting t.pulse separator ' · ')
check "leaves a value that matches" "${out##*$'\n'}" "changed=0"

# == the real list
list=$(sed -n '/^# == the list$/,/^# == end of the list$/p' "$SCRIPT")
check "every pin is a full commit sha, not a tag or a short one" "" \
	"$(echo "$list" | awk '$1 == "git_plugin" && $4 !~ /^[0-9a-f]{40}$/')"
for p in "$HERE"/patches/*.patch; do
	[ -e "$p" ] || continue
	id=$(basename "$p" .patch)
	check "patches/$id.patch belongs to a git_plugin in the list" \
		"$(echo "$list" | awk -v id="$id" '$1 == "git_plugin" && $2 == id' | wc -l | tr -d ' ')" "1"
done

echo
[ "$FAILED" -eq 0 ] && echo "all passed" || { echo "some failed"; exit 1; }
