#!/usr/bin/env bash
# Offer the extensions in extensions.txt to Chrome, from the Web Store.
#
# Chrome syncs extensions, but only into a profile signed in to that account, and
# only what was once clicked by hand. This writes one <id>.json per extension
# into Chrome's "External Extensions" folder; on its next start Chrome asks to
# enable each one. Removing it in Chrome sticks: it is not offered again.
# Not ExtensionInstallForcelist, which would lock the extension in place.
#
# usage: extensions.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
list="${CHROME_EXTENSIONS_LIST:-$here/extensions.txt}"

# The system folder on both, hence sudo. macOS also reads one inside the user's
# Chrome profile, but that folder carries com.apple.macl and a terminal without
# Full Disk Access cannot write there (see prefs.sh).
case "$(uname -s)" in
Darwin) folder="/Library/Application Support/Google/Chrome/External Extensions" ;;
*)      folder=/usr/share/google-chrome/extensions ;;
esac
sudo=sudo
if [ -n "${CHROME_EXTERNAL_EXTENSIONS:-}" ]; then
	folder=$CHROME_EXTERNAL_EXTENSIONS
	sudo=
fi

# Every id is checked before anything is written, so a typo leaves no half-applied list.
ids=()
while read -r id _; do
	case "$id" in "" | "#"*) continue ;; esac
	[[ "$id" =~ ^[a-p]{32}$ ]] || { echo "not a Chrome extension id: $id" >&2; exit 1; }
	ids+=("$id")
done <"$list"

# ponytail: an id dropped from the list keeps its file. Deleting it uninstalls
# the extension in Chrome, so that stays a hand step: rm "$folder/<id>.json".
$sudo mkdir -p "$folder"
for id in "${ids[@]}"; do
	printf '{"external_update_url": "https://clients2.google.com/service/update2/crx"}\n' |
		$sudo tee "$folder/$id.json" >/dev/null
	echo "offered $id"
done
echo "restart Chrome and enable them when it asks"
