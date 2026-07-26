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

### Internal panel black after resume (upstream KWin bug, unfixed)

Sporadically after waking, the internal panel stays black and the session acts as
if an external monitor were attached. **This is not fixable from this repo** — it
is an upstream regression, documented here so it isn't re-diagnosed from scratch.

Signature, at the exact second of resume:

```
kwin_wayland_drm: Atomic modeset test failed! No such file or directory   (x12)
kwin_wayland_drm: Failed to open drm device
```

KWin has lost its DRM device, so anything that talks *to* KWin (`kscreen-doctor`,
KScreen profiles) is powerless — a resume hook calling `kscreen-doctor` was tried
and removed for this reason. Matches [KDE Bug 520008](https://bugs.kde.org/show_bug.cgi?id=520008)
(Ubuntu 26.04 + i915 + external monitor + Plasma 6.6).

Timeline on this machine: `Failed to open drm device` first appears **2026-05-18**,
the day of the 26.04 upgrade. Suspend/resume worked reliably for months before that
(one boot in June logged 28 clean resumes). X11 is not an escape hatch — Plasma's
X11 session is no longer packaged in 26.04.

Two red herrings, recorded so they aren't chased again:

- `i915 ... *ERROR* Atomic update failure on pipe A` — vblank-timing warnings
  (missed flip deadline), cosmetic. They still occur with PSR disabled via the
  kernel cmdline, and are **unrelated** to this bug. Not to be confused with
  KWin's `Atomic modeset test failed`, which is the real signature.
- PSR (`i915.enable_psr=0`) — plausible, unproven, did not fix it.

Recovery when it happens: restart the compositor from a TTY (Ctrl+Alt+F3) —
`systemctl --user restart plasma-kwin_wayland.service`. This restarts the Wayland
session, so unsaved work in running apps is at risk.

## Hardware / OS context

- ThinkPad T480
- Kubuntu 26.04, KDE Plasma 6, systemd 259
