# Internal panel black after resume — kernel or compositor, still open

| Field | Value |
|---|---|
| Status | Mitigated (pinned to kernel 7.0.0-22), upstream unfixed. **7.0.0-29 is the open lead** — clean so far, never tested when the pin was set |
| Affects | Kubuntu 26.04, KDE Plasma 6.6.6 (Wayland) |
| Upstream | [Launchpad #2161881](https://bugs.launchpad.net/ubuntu/+source/linux/+bug/2161881) — New, unassigned, no maintainer response |
| First seen | 2026-05-18 (the 26.04 release upgrade) |
| Re-measured | 2026-08-31, after the first pass mixed a startup message into the failure count |

## Symptom

After waking, the internal panel stays black and the session behaves as if an
external monitor were attached. KWin cannot drive the panel; nothing that talks
*to* KWin can repair it.

Two distinct signatures appear at the second of resume, and the difference
matters — they are different failures, not two spellings of one:

```
kwin_wayland_drm: Atomic modeset test failed! Invalid argument     (EINVAL)
kwin_wayland_drm: Atomic modeset test failed! Permission denied    (EACCES)
kwin_wayland_drm: Failed to open drm device
```

**EINVAL** is a rejected mode. **EACCES** is a lost DRM master — KWin still has
the device but is no longer allowed to drive it. The EACCES variant was missed
on the first pass and is the one that matches the closest upstream report; see
*Where this is already reported* below.

### One message is noise, and it corrupted the first measurement

`Failed to open drm device` has two forms:

| Line | Meaning |
|---|---|
| `Failed to open drm device /dev/dri/renderD128` | Render-node probe. Fires **once per boot on every boot, including clean ones.** Benign |
| `Failed to open drm device` (no path) | `DrmBackend::addGpu()` gave up after ~5 s of retries. **This is the real one** |

The first version of this document counted both, which is why it reported "0"
for -22 and "9" for -28. Counting only the bare form makes the result cleaner
*and* stronger.

## Measurement

Whole journal history, normalised by suspend count (`PM: suspend entry`),
kernel the only variable:

| kernel | suspends | `Failed to open` (bare) | modeset EINVAL | modeset EACCES |
|--------|---------:|------------------------:|---------------:|---------------:|
| 7.0.0-22 | 38 | **0** | 22 | 2 |
| 7.0.0-28 | 8 | **12** | 102 | 0 |
| 7.0.0-29 | 5 | **0** | 0 | 0 |
| 7.0.0-30 | 1 | **3** | 0 | 4 |

Read it with the sample sizes in mind:

- **-22 vs -28 holds, and harder than before** — 0 failures in 38 suspends
  against 12 in 8. The pin was the right call.
- **The -22 EINVAL count is one bad boot, not a background rate.** All 22 are
  in a single boot with 2 suspends; the other 36 suspends are clean. The earlier
  framing — "rare enough to live with" — was wrong. It is not a low rate, it is
  one anomaly.
- **-29 and -30 were never tested when the pin was set.** -29 is clean across
  5 suspends in 2 boots. That is a small sample, not a verdict, but it is the
  cheapest thing left to try.
- **-30's failures are all EACCES**, after a 62-hour suspend — a different
  signature and a confounded data point. One suspend proves nothing.

Reproduce:

```
uname -r
journalctl -b | grep -c 'PM: suspend entry'                              # denominator
journalctl -b | grep -cE 'Failed to open drm device *$'                  # the real signature
journalctl -b | grep -c 'Atomic modeset test failed! Invalid argument'
journalctl -b | grep -c 'Atomic modeset test failed! Permission denied'
```

## Cause — narrowed to -28, not -27

The Ubuntu kernel changelogs from -22 forward (real upload order is
22 → 26 → 27 → 28 → 29 → 30; 23–25 do not exist):

| upload | contents |
|--------|----------|
| -26 | stable v7.0.1–v7.0.6. No i915 |
| -27 | CVEs, packaging resync, `[Config] Disable NOVA_CORE`. **Zero drm, i915, display, PM, suspend or ACPI entries** |
| -28 | stable v7.0.7–v7.0.12. **The only upload in the range with display content** — the `drm/i915/backlight` series, `drm/i915/dp: Avoid joiner for eDP if not enabled in VBT`, `drm/i915/aux: use polling when irqs are unavailable`, PSR DC6 changes |
| -29 | amdgpu + CVEs. No i915 |
| -30 | one CVE (openvswitch). Nothing graphics or PM |

So there is a mechanism for -28 and **none for -27**. The Launchpad report says
"between 7.0.0-22 and 7.0.0-27/-28"; the -27 half has no code behind it and
weakens the report. Narrowing it to -28 strengthens it, because -28 is exactly
where the i915 batch landed.

Also worth knowing: Ubuntu **reverted** `drm/i915/backlight: Remove
try_vesa_interface` in -31 (still in -proposed) for a backlight regression,
[LP #2161309](https://launchpad.net/ubuntu/resolute/+source/linux/+changelog).
-30 still carries the unreverted version.

Corroborated by [Framework 13 / Intel / Ubuntu 26.04](https://community.frame.work/t/ubuntu-26-04-suspend-resume-crash-on-kernel-7-0-0-27/83394)
— *"Reverting back to 7.0.0-22 fixed the issue for me."* Still a single post
with no replies as of 2026-08-31.

## Where this is already reported

Nobody has fixed this. Three KDE bugs are relevant, and the triage on them is
part of why it is still open.

- **[KDE #516038](https://bugs.kde.org/show_bug.cgi?id=516038)** — *"kwin_wayland
  loses DRM master during S3 suspend and never re-acquires it on resume."*
  Fedora 43, kernel 6.18.9, so it **predates the 7.0 series entirely**. The
  reporter proved via SysRq that the kernel is fine: after userspace is killed
  the kernel reclaims DRM master and fbcon lights the panel. KWin has no
  recovery path. This is the closest match to the **EACCES** signature above,
  and it is evidence against the kernel being the whole story.

- **[KDE #520008](https://bugs.kde.org/show_bug.cgi?id=520008)** — ThinkPad X1
  Carbon, i915, Ubuntu 26.04, **kernel 7.0.0-15**, KWin 6.6.4, same messages.
  The closest public report to this machine. Closed as a duplicate of #518058
  six hours after filing, with no analysis comment and no KWin developer
  involved. That closure looks wrong: #518058 is filed against *plasmashell*,
  and its fix touches `libkworkspace/outputorderwatcher.cpp` — code in the
  plasmashell process that consumes the `kde_output_order_v1` protocol. It
  cannot cause or prevent an atomic modeset in KWin. Closing a compositor bug
  into a shell bug buries it. Note it is on an ABI *older* than -22, which the
  kernel-regression theory does not explain.

- **[KDE #524883](https://bugs.kde.org/show_bug.cgi?id=524883)** — crash in
  `DrmGpu::pageFlipHandler()` on resume, bisected to KWin commit `41097b10`
  *"backends/drm: remove DrmGpu when it becomes inactive"*, fixed by reverting.
  KWin 6.7.80 only, so not this machine — but it shows the "compositor loses its
  DRM device on resume" failure class is live and unresolved in KWin's DRM
  backend, across Intel, NVIDIA and Qualcomm alike.

## Mitigation

GRUB boots 7.0.0-22 by default via `GRUB_DEFAULT` in `/etc/default/grub`:

```
GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux 7.0.0-22-generic"
```

Newer kernels stay installed and are offered in the menu. **This is a hold, not
a home** — 7.0.0-22 misses three months of kernel security fixes. See
*Next* below for how it ends.

## Recovery, if it happens anyway

Try these in order — the first two are also diagnostics, which is the point.

1. **`Alt+SysRq+E`.** If the panel lights up under fbcon, the kernel and GPU are
   fine and the fault is KWin's, exactly as in #516038. This single test would
   split the kernel theory from the compositor theory and has not been run yet.
2. **`Ctrl+Alt+F3`, then back.** If a VT switch restores output, the fault is in
   KWin's session/device re-acquisition rather than in i915. Cheaper than a
   restart and loses nothing.
3. **Restart the compositor**, from a TTY:

   ```
   systemctl --user restart plasma-kwin_wayland.service
   ```

   This restarts the Wayland session, so unsaved work in running apps is at
   risk. That it is *KWin* that needs restarting — not plasmashell — is itself
   evidence the fault sits above the shell.

## Next

1. **Test 7.0.0-29.** Already installed, clean across its 5 suspends, and three
   months of CVE fixes newer than the pin. Run a deliberate series of suspends
   on it and count with the commands above. This is the likely end of the pin.
2. **Run the SysRq test** at the next black screen, before restarting anything.
3. **Re-qualify the Launchpad report** — narrow to -28, correct the metric, add
   the EACCES variant, and reference #520008 with a request to reopen it against
   product `kwin`.

## Dead ends

Recorded with the evidence that killed them, so they aren't chased again.

- **Upgrading Plasma** — no path exists and the target is wrong anyway. The
  [Kubuntu Backports PPA ships 6.6.6 for resolute](https://launchpad.net/~kubuntu-ppa/+archive/ubuntu/backports),
  identical to what the archive already has, because **Plasma 6.6 is the LTS
  series**, supported to 2029. Reaching 6.7 means leaving packaged Kubuntu
  entirely. And it would not help: the fix that looked relevant (#518058, in
  6.7.0) is the plasmashell layer, its reporter says the bug survived into 6.7,
  and KWin 6.7.80 carries an *active* resume regression (#524883). Nothing in
  6.7 or 6.8 addresses DRM-master re-acquisition, which is the EACCES signature
  here.
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
  has already lost the device. Written, then removed.
- **The MST dock** — the failure also occurs at session start with no suspend
  involved, so docking is not the trigger.
- **Blaming 7.0.0-27** — the changelog from -22 to -27 contains no drm, i915,
  display, PM or ACPI change at all. There is no mechanism. The regression
  window is -28.
