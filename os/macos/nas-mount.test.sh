#!/bin/sh
# Self-check for nas-mount.sh. What it would get wrong silently: mounting the
# share a second time, or raising an error dialog when the NAS is out of reach.
set -eu

script="$(cd "$(dirname "$0")" && pwd)/.local/bin/nas-mount.sh"
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fails=0

for tool in mount nc osascript; do
	cat > "$t/$tool" <<STUB
#!/bin/sh
echo "$tool \$*" >> "$t/calls"
[ "$tool" = mount ] && cat "$t/mounts"
[ "$tool" = nc ] && exit "\$(cat "$t/nc-rc")"
exit 0
STUB
	chmod +x "$t/$tool"
done

check() { # check <behaviour> <mounts> <nc exit code> <osascript calls expected>
	printf '%s\n' "$2" > "$t/mounts"
	echo "$3" > "$t/nc-rc"
	: > "$t/calls"
	PATH="$t:$PATH" "$script"
	got=$(grep -c '^osascript' "$t/calls" || true)
	if [ "$got" = "$4" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1 (osascript ran $got times)"
		fails=$((fails + 1))
	fi
}

check 'mounts when the share is missing and the NAS answers' '/dev/disk1 on / (apfs)' 0 1
check 'stays quiet when the NAS is out of reach' '/dev/disk1 on / (apfs)' 1 0
check 'leaves a Bonjour mount alone' '//pi5@NAS._smb._tcp.local/ssd on /Volumes/ssd (smbfs, nodev)' 0 0
check 'leaves a mount at a shifted mount point alone' '//pi5@nas.local/ssd on /Volumes/ssd-1 (smbfs)' 0 0
check 'does not take another share for this one' '//pi5@nas.local/share on /Volumes/share (smbfs)' 0 1

exit "$fails"
