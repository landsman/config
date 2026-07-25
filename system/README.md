# System config

System-wide files (everything under `/`, not `$HOME`). The directory layout mirrors the filesystem so each file's destination is obvious from its repo path.

## Contents

| Path in repo                                            | Installs to                                              | What it does                                                                                                                                                              |
|---------------------------------------------------------|----------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `etc/pam.d/kde-smartcard`                               | `/etc/pam.d/kde-smartcard`                               | Overrides the vendor smartcard PAM stack — no smartcard hardware/SSSD on this box                                                                                         |
| `usr/lib/systemd/system-sleep/fix-validity-fingerprint` | `/usr/lib/systemd/system-sleep/fix-validity-fingerprint` | Restarts `python3-validity` + `open-fprintd` on resume so the Synaptics 06cb:009a reader doesn't hang unlock for ~25 s                                                    |
| `etc/modprobe.d/thinkpad_acpi.conf`                     | `/etc/modprobe.d/thinkpad_acpi.conf`                     | Enables `fan_control=1` on the `thinkpad_acpi` module so userspace (thinkfan) can drive the fan via `/proc/acpi/ibm/fan`                                                  |
| `etc/thinkfan.conf`                                     | `/etc/thinkfan.conf`                                     | Balanced fan curve for T480 dual-heatpipe cooler — reads `coretemp` (Package + 4 cores), drives `tpacpi` levels 0–7 + `disengaged`                                        |
| `etc/systemd/system/thinkpad-power-tune.service`        | `/etc/systemd/system/thinkpad-power-tune.service`        | Caps Intel RAPL PL1 to 20 W and max CPU frequency to 3.0 GHz at boot — without it BIOS leaves PL1 at 200 W and CPU pins at 95 °C under any sustained load (postgres, JVMs)|
| `etc/intel-undervolt.conf`                              | `/etc/intel-undervolt.conf`                              | Undervolt offsets for i5-8350U: Core/Cache -75 mV, GPU -50 mV. Applied at boot + after resume by `intel-undervolt.service` (built from source, see Install)               |
| `etc/modprobe.d/i915-no-psr.conf`                       | `/etc/modprobe.d/i915-no-psr.conf`                       | Sets `enable_psr=0` on `i915` — disables Panel Self Refresh, which on the UHD 620 (Kaby Lake) leaves the internal eDP-1 panel black after resume (`Atomic update failure on pipe A` in dmesg). Needs `update-initramfs -u`, see Install |
| `usr/lib/systemd/system-sleep/fix-internal-display`     | `/usr/lib/systemd/system-sleep/fix-internal-display`     | Re-enables the internal panel (`eDP-1`) after resume when the lid is open — works around a KWin/Wayland + DisplayPort-MST-dock bug that leaves the internal output off and maps the desktop onto a disconnected external. Runs `kscreen-doctor` as the user after a 3 s MST settle |

## Install

```
sudo cp -r system/etc/. /etc/
sudo cp -r system/usr/. /usr/
sudo chmod +x /usr/lib/systemd/system-sleep/fix-validity-fingerprint /usr/lib/systemd/system-sleep/fix-internal-display
sudo systemctl disable --now open-fprintd-resume.service
sudo modprobe -r thinkpad_acpi && sudo modprobe thinkpad_acpi
sudo systemctl daemon-reload
sudo systemctl enable --now thinkfan.service thinkpad-power-tune.service
sudo update-initramfs -u
```

`update-initramfs -u` is required for `i915-no-psr.conf`: `i915` loads early from the initramfs (KMS + `splash`), so it reads its options from the initramfs copy of `modprobe.d`, not `/etc`. Without rebuilding, the option is silently ignored and PSR stays on. Verify with `lsinitramfs /boot/initrd.img-$(uname -r) | grep i915-no-psr`.

The `open-fprintd-resume.service` line is one-time cleanup: the stock service tries to call `Resume()` on a stale USB handle after wake and always crashes — our sleep hook replaces it.

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

## Hardware / OS context

- ThinkPad T480 (Synaptics Validity 06cb:009a fingerprint reader)
- Kubuntu 26.04, KDE Plasma 6, systemd 259
