#!/usr/bin/env bash
# Apply the macOS settings this repo owns — the System Settings panes that stow
# cannot reach, because macOS keeps them in `defaults`, not in dotfiles.
#
# A script and not a stow package: the plists under ~/Library/Preferences are
# binary, rewritten by cfprefsd whenever it feels like it, and full of per-machine
# noise (window frames, analytics stamps, Dock icon bookmarks). Symlinking one
# into git would track that noise and lose the settings. So only the keys listed
# here are written, and everything else is left as the machine has it.
#
# To add a setting: change it in System Settings, then diff what moved —
#   defaults read > /tmp/before   # …click the thing…   defaults read > /tmp/after
#   diff /tmp/before /tmp/after
# and paste the key here with its type from `defaults read-type <domain> <key>`.
#
# usage: defaults.sh [--dry-run]
set -eu

[ "${1:-}" != "--dry-run" ] || DRY_RUN=1
: "${DRY_RUN:=}"

# ponytail: one helper, one line per setting. No apply/verify/rollback layer —
# `defaults write` is already idempotent, and the diff above is the review.
# --dry-run always quotes the key, including the ones that need no quoting: the
# line stays copy-pasteable, and the test can pull the key back out of it with
# one pattern instead of guessing where a key with spaces ends.
w() {
	if [ -n "$DRY_RUN" ]; then printf "defaults write %s '%s' %s\n" "$1" "$2" "${*:3}"
	else defaults write "$@"; fi
}

#
# Menu bar — what is in it, and in what order
#
# The positions are pixels from the right edge of the screen, so a wider display
# spreads them out rather than reordering them; the order is what these encode.
# BentoBox-0 is the Control Center icon itself.
w com.apple.controlcenter "NSStatusItem Preferred Position Battery"    -float 294
w com.apple.controlcenter "NSStatusItem Preferred Position Sound"      -float 355
w com.apple.controlcenter "NSStatusItem Preferred Position WiFi"       -float 336
w com.apple.controlcenter "NSStatusItem Preferred Position BentoBox-0" -float 124
w com.apple.controlcenter "NSStatusItem VisibleCC Battery"    -bool true
w com.apple.controlcenter "NSStatusItem VisibleCC Sound"      -bool true
w com.apple.controlcenter "NSStatusItem VisibleCC WiFi"       -bool true
w com.apple.controlcenter "NSStatusItem VisibleCC Clock"      -bool true
w com.apple.controlcenter "NSStatusItem VisibleCC BentoBox-0" -bool true

# The clock: day of the week, 12-hour, no date.
w com.apple.menuextra.clock ShowDayOfWeek -bool true
w com.apple.menuextra.clock ShowAMPM      -bool true
w com.apple.menuextra.clock ShowDate      -bool false

#
# Dock
#
w com.apple.dock tilesize                 -float 47
w com.apple.dock mineffect                -string scale
w com.apple.dock "minimize-to-application" -bool true
w com.apple.dock launchanim               -bool false
w com.apple.dock "show-recents"           -bool false
# Bottom-right hot corner: 14 = Quick Note. The modifier is written too — left
# unset it is nil rather than 0, and the corner then needs a held key.
w com.apple.dock "wvous-br-corner"   -int 14
w com.apple.dock "wvous-br-modifier" -int 0

#
# Finder
#
w com.apple.finder AppleShowAllFiles -bool true
w NSGlobalDomain AppleShowAllExtensions -bool true

#
# System-wide
#
w NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically -bool true   # light/dark by time
w NSGlobalDomain AppleMiniaturizeOnDoubleClick -bool false
w NSGlobalDomain AppleWindowTabbingMode -string always
w NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
w NSGlobalDomain NSSmartReplyEnabled -bool false

# Czech habits on a US system: metric, Celsius, Monday first, dd.MM.y.
w NSGlobalDomain AppleMetricUnits      -bool true
w NSGlobalDomain AppleMeasurementUnits -string Centimeters
w NSGlobalDomain AppleTemperatureUnit  -string Celsius
w NSGlobalDomain AppleFirstWeekday          -dict gregorian 2
w NSGlobalDomain AppleICUDateFormatStrings  -dict 1 "dd.MM.y"

#
# Trackpad — tap to click, on the built-in and on a paired Magic Trackpad
#
w com.apple.AppleMultitouchTrackpad Clicking -bool true
w com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
# The per-host twin of the same setting; without it the tap stops working after
# a logout, because this is the one the window server actually reads.
if [ -n "$DRY_RUN" ]; then
	echo "defaults -currentHost write NSGlobalDomain 'com.apple.mouse.tapBehavior' -int 1"
else
	defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
fi


[ -n "$DRY_RUN" ] && exit 0

# cfprefsd caches writes, and these apps only read at launch.
killall Dock Finder SystemUIServer ControlCenter 2>/dev/null || true
echo "applied - log out and back in for the rest"
