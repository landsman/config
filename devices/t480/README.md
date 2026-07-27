# ThinkPad T480

Everything specific to this laptop, independent of which OS is booted.

| | |
|---|---|
| Model | ThinkPad T480 (20L6S0CE41) |
| CPU | Intel Core i5-8350U |
| GPU | Intel UHD Graphics 620, Kaby Lake-R GT2 `[8086:5917]`, `i915` |
| BIOS | N24ET81W (1.56), 2025-09-06 |
| Storage | Samsung PM9C1a NVMe, LUKS-encrypted root |
| Dual boot | Kubuntu 26.04 (KDE) and Omarchy/Arch (Hyprland) |
| Dock | DisplayPort MST — BenQ 4K on DP-1, second panel on DP-4 |

## What lives where

| Path | What |
|------|------|
| `devices/t480/` (this package) | Shell aliases that need this hardware — `intel_gpu_top`, `thinkpad_acpi` fan/temps |
| [`system/`](../../system/README.md) | Root-owned tuning: thinkfan curve, RAPL/frequency caps, undervolt, i915 options |
| [`os/ubuntu/`](../../os/ubuntu) | KDE-side config used when Kubuntu is booted |
| [`os/arch/`](../../os/arch) | Hyprland-side config used when Omarchy is booted |

Only the *userland* part is stowed. The root-owned half is installed separately —
see [system/README.md](../../system/README.md).

## Known issues

### Internal panel black after resume — Ubuntu kernel regression (stay on 7.0.0-22)

After waking, the internal panel stayed black and the session behaved as if an
external monitor were attached. Signature at the second of resume:

```
kwin_wayland_drm: Atomic modeset test failed! Invalid argument   (x6-30)
kwin_wayland_drm: Failed to open drm device
```

**Cause: a regression in the Ubuntu kernel between 7.0.0-22 and 7.0.0-27/-28.**
Not mesa, not KDE. Booting 7.0.0-22 with no other change makes
`Failed to open drm device` disappear entirely.

Measured on this machine (same hardware, same session, kernel the only variable):

| kernel | `Failed to open drm device` | modeset failures |
|--------|-----------------------------|------------------|
| 7.0.0-22 | 0 | 12 at login, none on resume |
| 7.0.0-28 | 9 | 4–11 per resume |
| 7.0.0-28 + `KWIN_DRM_USE_MODIFIERS=0` | 9 | 21.5 per resume (worse) |

Aggregated across the full journal history, the per-resume failure rate is about
**12x higher** on -28 than on -22. The bug is not *absent* on -22 (24 occurrences
across 60 resumes) — just rare enough to live with.

**Reported upstream:** [Launchpad #2161881](https://bugs.launchpad.net/ubuntu/+source/linux/+bug/2161881)
— watch it before dropping the kernel pin.
Corroborated by [Framework 13 / Intel / Ubuntu 26.04](https://community.frame.work/t/ubuntu-26-04-suspend-resume-crash-on-kernel-7-0-0-27/83394)
(*"Reverting back to 7.0.0-22 fixed the issue for me"*). Symptom overlaps
[KDE Bug 520008](https://bugs.kde.org/show_bug.cgi?id=520008), but the fix is at
the kernel level.

**Mitigation:** GRUB boots 7.0.0-22 by default (`GRUB_DEFAULT` in
`/etc/default/grub`). Newer kernels stay installed and are offered in the menu —
retest them periodically and drop the pin once a fixed one ships. Trade-off:
7.0.0-22 misses later kernel security fixes, so this is a hold, not a home.

Recovery if it happens on a newer kernel: restart the compositor from a TTY
(Ctrl+Alt+F3) — `systemctl --user restart plasma-kwin_wayland.service`. This
restarts the Wayland session, so unsaved work in running apps is at risk.

#### Dead ends, recorded so they aren't chased again

- **mesa** — `libgbm1` jumped 25.2.8 → 26.0.3 on 2026-05-18, the same day the
  errors first appear, so it looked like a prime suspect. Disproven:
  `KWIN_DRM_USE_MODIFIERS=0` made the failure rate *worse*. That date is the
  26.04 release upgrade, when mesa, kernel and KWin all changed at once.
- **`i915 ... *ERROR* Atomic update failure on pipe A`** — vblank-timing warnings
  (missed flip deadline), cosmetic. Still occur with PSR disabled, unrelated. Not
  to be confused with KWin's `Atomic modeset test failed`, the real signature.
- **PSR** (`i915.enable_psr=0`) — plausible, unproven, did not fix it. Kept
  anyway as a harmless mitigation; see `system/etc/modprobe.d/i915-no-psr.conf`.
- **A `system-sleep` hook calling `kscreen-doctor`** — cannot work: KWin has lost
  the DRM device, so asking KWin to re-enable an output is meaningless. Removed.
