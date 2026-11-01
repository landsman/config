#!/bin/sh
# Puts the NAS back into Finder after macOS lost the mount, usually across a
# sleep or a network change. Run every minute by local.nas-mount; the password
# comes from the login keychain.
#
# Usage: nas-mount.sh
#
# Away from home the port check fails and nothing happens, so no error dialog.
# The Bonjour name, because nas.local resolves to a global IPv6 address first and
# the session then hangs on an address macOS rotates.
set -eu

host=NAS._smb._tcp.local
user=pi5
share=ssd

# By source rather than by /Volumes/ssd: a mount point left behind makes macOS
# mount at /Volumes/ssd-1, and that must still count as mounted.
mount | grep -Eq "^//$user@[^/]+/$share on .*\(smbfs" && exit 0
nc -z -G 2 nas.local 445 >/dev/null 2>&1 || exit 0
exec osascript -e "mount volume \"smb://$user@$host/$share\""
