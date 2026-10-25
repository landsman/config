#!/bin/sh
# Self-check for .local/bin/nas-mount.sh. nc, mount and osascript are stubbed,
# so this runs anywhere. What it would get wrong silently: mounting a share
# twice on every network change, or trying while away from home.
set -eu

script="$(cd "$(dirname "$0")" && pwd)/.local/bin/nas-mount.sh"
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

mkdir -p "$tmp/bin"
cat > "$tmp/bin/nc" <<'STUB'
#!/bin/sh
exit "${FAKE_NC:-0}"
STUB
cat > "$tmp/bin/mount" <<'STUB'
#!/bin/sh
cat "$FAKE_MOUNTS"
STUB
cat > "$tmp/bin/osascript" <<'STUB'
#!/bin/sh
echo "$2" >> "$FAKE_CALLS"
STUB
chmod +x "$tmp/bin/"*
export FAKE_MOUNTS="$tmp/mounts" FAKE_CALLS="$tmp/calls"

run() { : > "$FAKE_CALLS"; PATH="$tmp/bin:$PATH" "$script" "$@"; cat "$FAKE_CALLS"; }

: > "$FAKE_MOUNTS"
check "mounts both shares when none is mounted" \
	'mount volume "smb://pi5@nas.local/ssd"
mount volume "smb://pi5@nas.local/pi5"' "$(run)"

echo '//pi5@nas.local/ssd on /Volumes/ssd (smbfs, nodev, nosuid, mounted by me)' > "$FAKE_MOUNTS"
check "skips a share that is already mounted" \
	'mount volume "smb://pi5@nas.local/pi5"' "$(run)"

check "does not take ssd for a share named ss" \
	'mount volume "smb://pi5@nas.local/ss"' "$(run nas.local pi5 ss)"

: > "$FAKE_MOUNTS"
check "does nothing when the NAS does not answer" "" "$(FAKE_NC=1 run)"

exit "$fails"
