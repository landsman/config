# Internal panel black after resume — Ubuntu kernel regression

| Field | Value |
|---|---|
| Status | Mitigated (pinned to kernel 7.0.0-22), upstream unfixed |
| Affects | Kubuntu 26.04, KDE Plasma 6 (Wayland) |
| Upstream | [Launchpad #2161881](https://bugs.launchpad.net/ubuntu/+source/linux/+bug/2161881) |
| First seen | 2026-05-18 (the 26.04 release upgrade) |

## Symptom

After waking, the internal panel stays black and the session behaves as if an
external monitor were attached. Signature at the second of resume:

```
kwin_wayland_drm: Atomic modeset test failed! Invalid argument   (x6-30)
kwin_wayland_drm: Failed to open drm device
```

KWin has lost its DRM device — which is why nothing that talks *to* KWin can
repair it.

## Cause

A regression in the **Ubuntu kernel** between 7.0.0-22 and 7.0.0-27/-28. Not
mesa, not KDE. Booting 7.0.0-22 with no other change makes
`Failed to open drm device` disappear.

Measured on this machine, same hardware and session, kernel the only variable:

| kernel | `Failed to open drm device` | modeset failures |
|--------|-----------------------------|------------------|
| 7.0.0-22 | 0 | 12 at login, none on resume |
| 7.0.0-28 | 9 | 4–11 per resume |
| 7.0.0-28 + `KWIN_DRM_USE_MODIFIERS=0` | 9 | 21.5 per resume (worse) |

Aggregated over the full journal history the per-resume failure rate is roughly
**12x higher** on -28 than on -22. It is not *absent* on -22 (24 occurrences
across 60 resumes) — just rare enough to live with. That distinction matters: the
upstream report is framed as a frequency regression, not a new failure, because
the errors go back to 7.0.0-15.

Corroborated by [Framework 13 / Intel / Ubuntu 26.04](https://community.frame.work/t/ubuntu-26-04-suspend-resume-crash-on-kernel-7-0-0-27/83394)
— *"Reverting back to 7.0.0-22 fixed the issue for me."* Symptom overlaps
[KDE Bug 520008](https://bugs.kde.org/show_bug.cgi?id=520008), but the fix is at
the kernel level.

## Mitigation

GRUB boots 7.0.0-22 by default via `GRUB_DEFAULT` in `/etc/default/grub`:

```
GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux 7.0.0-22-generic"
```

Newer kernels stay installed and are offered in the menu. **This is a hold, not a
home** — 7.0.0-22 misses later kernel security fixes. Retest newer kernels
periodically, watch the Launchpad bug, and drop the pin once a fixed one ships:

```
uname -r
journalctl -b | grep -c 'Atomic modeset test failed'
journalctl -b | grep -c 'Failed to open drm device'    # this is the one that matters
```

## Recovery, if it happens anyway

From a TTY (Ctrl+Alt+F3):

```
systemctl --user restart plasma-kwin_wayland.service
```

This restarts the Wayland session, so unsaved work in running apps is at risk.

## Dead ends

Recorded with the evidence that killed them, so they aren't chased again.

- **mesa** — `libgbm1` jumped 25.2.8 → 26.0.3 on 2026-05-18, the exact day the
  errors first appear, and `libgbm1` is what KWin allocates buffers through, so
  it looked like a prime suspect. Disproven by measurement:
  `KWIN_DRM_USE_MODIFIERS=0` made the failure rate *worse*. That date is the
  26.04 release upgrade, when mesa, kernel and KWin all moved at once.
- **`i915 ... *ERROR* Atomic update failure on pipe A`** — vblank-timing warnings
  (missed flip deadline), cosmetic. Still occur with PSR disabled via the kernel
  cmdline, and occur when everything works. Not to be confused with KWin's
  `Atomic modeset test failed`, which is the real signature.
- **PSR** (`i915.enable_psr=0`) — plausible, unproven, did not fix it. Kept as a
  harmless mitigation; see [`system/etc/modprobe.d/i915-no-psr.conf`](../../system/etc/modprobe.d/i915-no-psr.conf).
- **A `system-sleep` hook calling `kscreen-doctor`** — cannot work, since KWin
  has already lost the DRM device. Written, then removed.
- **The MST dock** — the failure also occurs at session start with no suspend
  involved, so docking is not the trigger.
