#!/usr/bin/env bash
# Apps for the Omarchy/Arch box that the Brewfile cannot install — the GUI one
# and the Linux-only tool — from the AUR. Run by `make apps` right after
# `brew bundle`, which finds this file as os/$(OS)/install-apps.sh; an OS without
# one is skipped, which is how macOS needs no guard.
#
# The mirror of the Kubuntu installer next door, with two differences that come
# from the AUR rather than apt:
#
#   - No repo, no pinned key. An AUR package is built from a PKGBUILD by makepkg,
#     so what vouches for it is the recipe and its maintainer, not a signing
#     fingerprint — there is nothing fetched to pin, and so nothing for the test
#     beside this to check beyond which packages are asked for.
#   - Never root. yay refuses to run as root and calls sudo itself for the pacman
#     half, so this script does not re-exec under sudo the way the apt one does.
#
# Idempotent and quiet: installed packages are filtered out first, so a re-run on
# a provisioned machine calls yay with nothing and returns without building.
#
#   bash os/arch/install-apps.sh

set -euo pipefail

# The AUR packages this repo installs on Arch. claude-desktop repackages
# Anthropic's official .deb for pacman (see the README); hyprmon-bin is the
# monitor TUI whose profiles are stowed under .config/hyprmon.
PACKAGES=(claude-desktop hyprmon-bin)

if ! command -v yay >/dev/null; then
	echo "yay not found - Arch here installs AUR apps with it, and Omarchy ships it." >&2
	echo "On a box without one: sudo pacman -S --needed base-devel git, then build yay." >&2
	exit 1
fi

# pacman -Qq exits non-zero for a package that is not installed, which is the
# whole check; its stderr on a miss is the expected path, not an error.
MISSING=()
for pkg in "${PACKAGES[@]}"; do
	pacman -Qq "$pkg" >/dev/null 2>&1 || MISSING+=("$pkg")
done

if [ ${#MISSING[@]} -eq 0 ]; then
	echo "== AUR apps: all ${#PACKAGES[@]} installed"
	exit 0
fi

echo "== AUR apps: missing ${MISSING[*]}"
echo "==> Installing ${MISSING[*]}"
# --needed is belt-and-braces after the filter above; --noconfirm matches the apt
# installer's -y, so `make apps` runs start to finish. yay still prompts once for
# the sudo password for the pacman half — the one interaction left.
yay -S --needed --noconfirm "${MISSING[@]}"
