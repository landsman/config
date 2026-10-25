#!/bin/sh
# Mounts the home NAS's Samba shares, run by local.nas-mount at login and on
# every network change, so they are there after arriving home too.
#
#   nas-mount.sh [host] [user] [share...]   defaults: nas.local pi5 ssd pi5
#
# The password comes from the Keychain, saved the first time the share was
# mounted by hand in Finder with "Remember this password". Without it this does
# nothing silently (osascript fails, no dialog), so mount once by hand first.
#
# Away from home the NAS does not answer, and the port check skips the mount
# rather than have every network change pop a "server not found" dialog.
set -eu

host=${1:-nas.local}
user=${2:-pi5}
if [ $# -gt 2 ]; then shift 2; else set -- ssd pi5; fi

nc -z -G 3 "$host" 445 >/dev/null 2>&1 || exit 0
for share in "$@"; do
	mount | grep -q "@$host/$share on " && continue
	osascript -e "mount volume \"smb://$user@$host/$share\"" >/dev/null || echo "nas-mount: $share failed" >&2
done
