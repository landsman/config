# ThinkPad T480

Config specific to this laptop, independent of which OS is booted. Triple-boots
Kubuntu 26.04 (KDE), Omarchy/Arch (Hyprland) and Windows 11.

## Docs

- [Hardware](docs/hardware.md) — specs, operating systems, and how to re-read them
- [Upgrades / to consider](docs/upgrades.md) — planned and parked hardware changes
- [Known issues](#known-issues)

## What lives where

| Path | What |
|------|------|
| `devices/t480/` (this package) | Shell aliases that need this hardware — `intel_gpu_top`, `thinkpad_acpi` fan/temps |
| [`system/`](../../system/README.md) | Root-owned tuning: thinkfan curve, RAPL/frequency caps, undervolt, i915 options |
| [`os/ubuntu/`](../../os/ubuntu) | KDE-side config, used when Kubuntu is booted |
| [`os/arch/`](../../os/arch) | Hyprland-side config, used when Omarchy is booted |

Only the userland half is stowed into `$HOME`. The root-owned half is installed
separately — see [system/README.md](../../system/README.md).

## Known issues

One file per issue in [`docs/issues/`](docs/issues), so this list stays a list.

| Issue | Status |
|-------|--------|
| [Internal panel black after resume](docs/issues/internal-panel-black-on-resume.md) | Mitigated — pinned to kernel 7.0.0-22, [upstream](https://bugs.launchpad.net/ubuntu/+source/linux/+bug/2161881) unfixed |

## Adding to this package

Files here are symlinked into `$HOME` by `make stow`, so anything that is *not*
meant to land in the home directory has to be listed in `.stow-local-ignore` —
that is why `README.md` and `docs/` are in it. Note that a local ignore file
replaces stow's entire default list rather than adding to it.
