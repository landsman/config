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
written=0   # counted by the helpers below, so the closing line can say how many

# ponytail: one helper, one line per setting. No apply/verify/rollback layer —
# `defaults write` is already idempotent, and the diff above is the review.
# --dry-run always quotes the key, including the ones that need no quoting: the
# line stays copy-pasteable, and the test can pull the key back out of it with
# one pattern instead of guessing where a key with spaces ends.
w() {
	written=$((written + 1))
	if [ -n "$DRY_RUN" ]; then printf "defaults write %s '%s' %s\n" "$1" "$2" "${*:3}"
	else defaults write "$@"; fi
}

# The -currentHost twin: same keys, but a per-machine plist under ByHost, which
# is where the window server and Control Center actually read some of them from.
wh() {
	written=$((written + 1))
	if [ -n "$DRY_RUN" ]; then printf "defaults -currentHost write %s '%s' %s\n" "$1" "$2" "${*:3}"
	else defaults -currentHost write "$@"; fi
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

# The modules themselves, which live per-host rather than in the domain above.
# 8 = in Control Center only, 16 = in the menu bar too, 2 = show while active,
# 0 = off. Anything not listed keeps whatever the machine has.
wh com.apple.controlcenter Sound            -int 16
wh com.apple.controlcenter ScreenMirroring  -int 2
wh com.apple.controlcenter NowPlaying       -int 8
wh com.apple.controlcenter FocusModes       -int 8
wh com.apple.controlcenter KeyboardBrightness -int 8
wh com.apple.controlcenter Spotlight        -int 8
wh com.apple.controlcenter VoiceControl     -int 8
wh com.apple.controlcenter Timer            -int 0

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
# Window tiling and Stage Manager
#
# No gap between tiled windows — the margin is the whole reason macOS tiling
# looks worse than a real tiler.
w com.apple.WindowManager EnableTiledWindowMargins -bool false
# Clicking the wallpaper reveals the desktop only in Stage Manager, not always.
w com.apple.WindowManager HideDesktop -bool true
w com.apple.WindowManager AutoHide -bool true
w com.apple.WindowManager AppWindowGroupingBehavior -int 1

#
# Finder
#
w com.apple.finder AppleShowAllFiles -bool true
w NSGlobalDomain AppleShowAllExtensions -bool true
w com.apple.finder FXPreferredViewStyle -string Nlsv   # list view
w com.apple.finder NewWindowTarget      -string PfAF   # new window opens All Files
w com.apple.finder "_FXSortFoldersFirst" -bool true
w com.apple.finder ShowRecentTags -bool false
# On the desktop: mounted volumes yes, the internal disk no.
w com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
w com.apple.finder ShowRemovableMediaOnDesktop     -bool true
w com.apple.finder ShowMountedServersOnDesktop     -bool true
w com.apple.finder ShowHardDrivesOnDesktop         -bool false

#
# System-wide
#
w NSGlobalDomain "com.apple.swipescrolldirection" -bool false   # not "natural"
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
wh NSGlobalDomain "com.apple.mouse.tapBehavior" -int 1

#
# Privacy
#
w com.apple.AdLib allowApplePersonalizedAdvertising -bool false
w com.apple.assistant.support "Dictation Auto Punctuation Enabled" -bool false

#
# Spotlight — what is allowed to show up in results
#
# One array, and its name lies: `EnabledPreferenceRules` lists what is turned
# *off*. Every entry is a row switched off in System Settings > Spotlight, and
# a row left at Apple's default is simply absent. Verified by diffing
# `defaults read` across a flip of the Files and Folders switches — both
# appeared in this array the moment they went dark.
#
# So this is written as one array and not per row: the whole list is the state,
# and `-array` replaces it. Adding a row here means turning it off.
#
# This is a *results* filter and nothing more. `mds` keeps indexing every file
# either way — a probe file dropped in ~/projects with Files and Folders both
# off was still in `mdfind` twenty seconds later. Stopping the indexer is
# `make macos-spotlight-off`, which is a different decision and a separate
# target.
w com.apple.Spotlight EnabledPreferenceRules -array \
	"Custom.relatedContents" \
	"com.apple.iBooksX" "com.apple.calculator" "com.apple.iCal" "com.apple.clock" \
	"com.apple.AddressBook" "com.apple.Dictionary" "com.apple.FaceTime" \
	"com.apple.Numbers" "com.apple.Pages" "com.apple.mobilephone" \
	"com.apple.Photos" "com.apple.podcasts" "com.apple.tips" \
	"net.whatsapp.WhatsApp" \
	"System.files" "System.folders" "System.iphoneApps"

#
# Keyboard layouts — Czech and U.S., plus the emoji picker
#
# An array of dicts, so it goes in as an old-style plist literal rather than as
# one key per value. The IDs are Apple's, and the string/integer split is theirs
# too: it is what `defaults read` shows, and the layout is not found if it is
# normalised. The order here is the order in the input menu.
w com.apple.HIToolbox AppleEnabledInputSources -array \
	'{ InputSourceKind = "Keyboard Layout"; "KeyboardLayout ID" = "-14193"; "KeyboardLayout Name" = Czech; }' \
	'{ InputSourceKind = "Keyboard Layout"; "KeyboardLayout ID" = 0; "KeyboardLayout Name" = "U.S."; }' \
	'{ "Bundle ID" = "com.apple.CharacterPaletteIM"; InputSourceKind = "Non Keyboard Input Method"; }'

#
# Keyboard shortcuts — 17 of the 21 system ones are off
#
# A whole domain, not a key list: the shortcuts are one nested dict of numeric
# IDs, and 17 `defaults write ... -dict-add` lines would be less readable than
# the plist itself. Exported as XML, so a change to it shows up as a diff:
#   defaults export com.apple.symbolichotkeys bin/macos/symbolichotkeys.plist
#   plutil -convert xml1 bin/macos/symbolichotkeys.plist
# `import` replaces the domain outright, which is the intent — the domain holds
# nothing but these shortcuts.
hotkeys="$(cd "$(dirname "$0")" && pwd)/symbolichotkeys.plist"
if [ -n "$DRY_RUN" ]; then
	echo "defaults import com.apple.symbolichotkeys $hotkeys"
else
	defaults import com.apple.symbolichotkeys "$hotkeys"
fi

[ -n "$DRY_RUN" ] && exit 0

# cfprefsd caches writes, and these apps only read at launch.
killall Dock Finder SystemUIServer ControlCenter 2>/dev/null || true

# The keyboard shortcuts above are read by the window server, which a killall
# cannot reach — without this they arrive at the next login, which is a
# surprising thing for `make macos` to say. This is what System Settings itself
# calls to publish a change. Private, hence the full path and the `|| true`: if
# Apple moves it, the settings are still written and a logout still applies them.
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true

echo "$written settings written (menu bar, Dock, Finder, trackpad, formats, privacy, Spotlight results) plus the keyboard shortcuts from $(basename "$hotkeys"); Dock, Finder, the menu bar and Control Center restarted, so nothing here waits for a logout"
