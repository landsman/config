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
sudo cp -r devices/t480/system/etc/. /etc/
sudo cp -r devices/t480/system/usr/. /usr/
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
sudo cp devices/t480/system/etc/intel-undervolt.conf /etc/intel-undervolt.conf   # restore our values
sudo systemctl daemon-reload
sudo systemctl enable --now intel-undervolt.service
sudo intel-undervolt read   # verify Core/Cache -99.61 mV, GPU -49.80 mV
```

The service also hooks `suspend.target` and `hibernate.target` so the undervolt is re-applied after every wake — without it, MSR 0x150 resets to 0 mV on S3 resume.

## Considered: throttled — not installed

[erpalma/throttled](https://github.com/erpalma/throttled) is a Python daemon that
does, on a ~5 s loop, what two of the units above do once at boot: RAPL PL1/PL2
limits and the MSR 0x150 undervolt offsets. It is a **replacement for
`thinkpad-power-tune.service` + `intel-undervolt.service`, not an addition** —
running it alongside them puts two writers on the same MSRs and the last one to
write wins.

What it would add over the current stack:

| | |
|---|---|
| Disables BD PROCHOT (MSR 0x1FC) | The Lenovo EC asserts PROCHOT when *one* sensor hits ~80 °C and drops the CPU to ~400 MHz. Nothing tracked here touches it |
| Separate `AC` / `BATTERY` profiles | The current caps are one set of numbers regardless of power source |
| Re-applies on a timer | Makes the resume problem moot — the undervolt unit needs an explicit `suspend.target` hook for the same effect |
| Trip temp offset (MSR 0x1A2) | Not covered here either |

Why it is not installed: adopting it means retiring both units, moving
`intel-undervolt.conf`'s offsets (Core/Cache, GPU) into `[UNDERVOLT.AC]` /
`[UNDERVOLT.BATTERY]` in `/etc/lenovo_fix.conf`, and re-verifying under load
with `stui` (see the aliases package) — a rewrite of the thermal stack rather
than one more file. The trigger to actually do it is BD PROCHOT throttling
showing up in practice: a load where the package sits well under the 20 W cap
and the frequency still collapses.

If adopted: `yay -S throttled` on Arch, clone + `sudo ./install.sh` on Ubuntu,
then `systemctl disable --now intel-undervolt.service thinkpad-power-tune.service`
first.

## Hardware context

These files are all specific to the **ThinkPad T480** — see
[../README.md](../README.md) for the machine's specs, its
known issues (including the kernel pin for the black-panel-on-resume regression),
and what else is tracked for it.

Currently Ubuntu-flavoured: the install steps use `apt`, and the kernel pin is
about an Ubuntu kernel. The Arch side of the same hardware tuning isn't tracked.
