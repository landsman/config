# System config

System-wide files (everything under `/`, not `$HOME`). The directory layout mirrors the filesystem so each file's destination is obvious from its repo path.

## Contents

| Path in repo                                            | Installs to                                              | What it does                                                                                                                                                              |
|---------------------------------------------------------|----------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `etc/pam.d/kde-smartcard`                               | `/etc/pam.d/kde-smartcard`                               | Overrides the vendor smartcard PAM stack — no smartcard hardware/SSSD on this box                                                                                         |
| `etc/modprobe.d/thinkpad_acpi.conf`                     | `/etc/modprobe.d/thinkpad_acpi.conf`                     | Enables `fan_control=1` on the `thinkpad_acpi` module so userspace (thinkfan) can drive the fan via `/proc/acpi/ibm/fan`                                                  |
| `etc/thinkfan.conf`                                     | `/etc/thinkfan.conf`                                     | Balanced fan curve for T480 dual-heatpipe cooler — reads `coretemp` (Package + 4 cores), drives `tpacpi` levels 0–7 + `disengaged`                                        |
| `etc/systemd/system/thinkpad-power-tune.service`        | `/etc/systemd/system/thinkpad-power-tune.service`        | Caps Intel RAPL PL1 to 20 W and max CPU frequency to 3.0 GHz at boot — without it BIOS leaves PL1 at 200 W and CPU pins at 95 °C under any sustained load (postgres, JVMs)|
| `etc/intel-undervolt.conf`                              | `/etc/intel-undervolt.conf`                              | Undervolt offsets for i5-8350U: Core/Cache -75 mV, GPU -50 mV. Applied at boot + after resume by `intel-undervolt.service` (built from source, see Install)               |
| `etc/modprobe.d/i915-no-psr.conf`                       | `/etc/modprobe.d/i915-no-psr.conf`                       | Sets `enable_psr=0` on `i915` — disables Panel Self Refresh. Kept as a cheap, harmless mitigation for i915 resume glitches, but **unproven on this machine**: it did not fix the black panel after resume (see Known issues). Needs `update-initramfs -u`, see Install |

## Install

```
sudo cp -r system/etc/. /etc/
sudo cp -r system/usr/. /usr/
sudo chmod +x /usr/lib/systemd/system-sleep/fix-validity-fingerprint
sudo modprobe -r thinkpad_acpi && sudo modprobe thinkpad_acpi
sudo systemctl daemon-reload
sudo systemctl enable --now thinkfan.service thinkpad-power-tune.service
sudo update-initramfs -u
```

`update-initramfs -u` is required for `i915-no-psr.conf`: `i915` loads early from the initramfs (KMS + `splash`), so it reads its options from the initramfs copy of `modprobe.d`, not `/etc`. Without rebuilding, the option is silently ignored and PSR stays on. Verify with `lsinitramfs /boot/initrd.img-$(uname -r) | grep i915-no-psr`.

The `modprobe` reload picks up `fan_control=1`. Thinkfan refuses to start without it.

`intel-undervolt` is not in Ubuntu repos — build from source (https://github.com/kitsunyan/intel-undervolt):

```
sudo apt install -y build-essential pkg-config libcap-dev libsystemd-dev
git clone https://github.com/kitsunyan/intel-undervolt.git /tmp/intel-undervolt
cd /tmp/intel-undervolt
./configure --enable-systemd --unitdir=/usr/lib/systemd/system
make
sudo make install   # NOTE: this overwrites /etc/intel-undervolt.conf with defaults
sudo cp system/etc/intel-undervolt.conf /etc/intel-undervolt.conf   # restore our values
sudo systemctl daemon-reload
sudo systemctl enable --now intel-undervolt.service
sudo intel-undervolt read   # verify Core/Cache -99.61 mV, GPU -49.80 mV
```

The service also hooks `suspend.target` and `hibernate.target` so the undervolt is re-applied after every wake — without it, MSR 0x150 resets to 0 mV on S3 resume.

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

Measured on this machine (failures per resume, same hardware, same session):

| kernel | `Failed to open drm device` | modeset failures |
|--------|-----------------------------|------------------|
| 7.0.0-22 | 0 | 12 at login, none on resume |
| 7.0.0-28 | 9 | 4–11 per resume |
| 7.0.0-28 + `KWIN_DRM_USE_MODIFIERS=0` | 9 | 21.5 per resume (worse) |

**Reported upstream:** [Launchpad #2161881](https://bugs.launchpad.net/ubuntu/+source/linux/+bug/2161881)
(ubuntu/+source/linux) — watch it before dropping the kernel pin.

Corroborated by an independent report on the same distro and GPU vendor:
[Framework 13 / Intel / Ubuntu 26.04](https://community.frame.work/t/ubuntu-26-04-suspend-resume-crash-on-kernel-7-0-0-27/83394)
— *"Reverting back to 7.0.0-22 fixed the issue for me."*
Symptom overlaps [KDE Bug 520008](https://bugs.kde.org/show_bug.cgi?id=520008),
but the fix is at the kernel level.

**Mitigation:** GRUB boots 7.0.0-22 by default (`GRUB_DEFAULT` in
`/etc/default/grub`). Newer kernels stay installed and are offered in the menu —
retest them periodically and drop the pin once a fixed one ships. Trade-off:
7.0.0-22 misses later kernel security fixes, so this is a hold, not a home.

Dead ends, recorded so they aren't chased again:

- **mesa** — `libgbm1` jumped 25.2.8 → 26.0.3 on 2026-05-18, the same day the
  errors first appear, so it looked like a prime suspect. Disproven:
  `KWIN_DRM_USE_MODIFIERS=0` made the failure rate *worse*. The 05-18 date is the
  26.04 release upgrade, when mesa, kernel and KWin all changed at once.
- **`i915 ... *ERROR* Atomic update failure on pipe A`** — vblank-timing warnings
  (missed flip deadline), cosmetic. Still occur with PSR disabled, unrelated. Not
  to be confused with KWin's `Atomic modeset test failed`, the real signature.
- **PSR** (`i915.enable_psr=0`) — plausible, unproven, did not fix it.
- **A `system-sleep` hook calling `kscreen-doctor`** — cannot work: KWin has lost
  the DRM device, so asking KWin to re-enable an output is meaningless. Removed.

Recovery if it happens on a newer kernel: restart the compositor from a TTY
(Ctrl+Alt+F3) — `systemctl --user restart plasma-kwin_wayland.service`. This
restarts the Wayland session, so unsaved work in running apps is at risk.

## Hardware / OS context

- ThinkPad T480
- Kubuntu 26.04, KDE Plasma 6, systemd 259
