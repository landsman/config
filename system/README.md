# System config

System-wide files (everything under `/`, not `$HOME`). The directory layout mirrors the filesystem so each file's destination is obvious from its repo path.

## Contents

| Path in repo                                            | Installs to                                              | What it does                                                                                                                                                              |
|---------------------------------------------------------|----------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `etc/pam.d/kde-smartcard`                               | `/etc/pam.d/kde-smartcard`                               | Overrides the vendor smartcard PAM stack — no smartcard hardware/SSSD on this box                                                                                         |
| `usr/lib/systemd/system-sleep/fix-validity-fingerprint` | `/usr/lib/systemd/system-sleep/fix-validity-fingerprint` | Restarts `python3-validity` + `open-fprintd` on resume so the Synaptics 06cb:009a reader doesn't hang unlock for ~25 s                                                    |
| `etc/modprobe.d/thinkpad_acpi.conf`                     | `/etc/modprobe.d/thinkpad_acpi.conf`                     | Enables `fan_control=1` on the `thinkpad_acpi` module so userspace (thinkfan) can drive the fan via `/proc/acpi/ibm/fan`                                                  |
| `etc/thinkfan.conf`                                     | `/etc/thinkfan.conf`                                     | Balanced fan curve for T480 dual-heatpipe cooler — reads `coretemp` (Package + 4 cores), drives `tpacpi` levels 0–7 + `disengaged`                                        |
| `etc/systemd/system/thinkpad-power-tune.service`        | `/etc/systemd/system/thinkpad-power-tune.service`        | Caps Intel RAPL PL1 to 20 W and max CPU frequency to 2.5 GHz at boot — without it BIOS leaves PL1 at 200 W and CPU pins at 95 °C under any sustained load (postgres, JVMs)|

## Install

```
sudo cp -r system/etc/. /etc/
sudo cp -r system/usr/. /usr/
sudo chmod +x /usr/lib/systemd/system-sleep/fix-validity-fingerprint
sudo systemctl disable --now open-fprintd-resume.service
sudo modprobe -r thinkpad_acpi && sudo modprobe thinkpad_acpi
sudo systemctl daemon-reload
sudo systemctl enable --now thinkfan.service thinkpad-power-tune.service
```

The `open-fprintd-resume.service` line is one-time cleanup: the stock service tries to call `Resume()` on a stale USB handle after wake and always crashes — our sleep hook replaces it.

The `modprobe` reload picks up `fan_control=1`. Thinkfan refuses to start without it.

## Hardware / OS context

- ThinkPad T480 (Synaptics Validity 06cb:009a fingerprint reader)
- Kubuntu 26.04, KDE Plasma 6, systemd 259
