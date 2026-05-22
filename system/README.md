# System config

System-wide files (everything under `/`, not `$HOME`). The directory layout mirrors the filesystem so each file's destination is obvious from its repo path.

## Contents

| Path in repo                                            | Installs to                                              | What it does                                                                                                           |
|---------------------------------------------------------|----------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------|
| `etc/pam.d/kde-smartcard`                               | `/etc/pam.d/kde-smartcard`                               | Overrides the vendor smartcard PAM stack — no smartcard hardware/SSSD on this box                                      |
| `usr/lib/systemd/system-sleep/fix-validity-fingerprint` | `/usr/lib/systemd/system-sleep/fix-validity-fingerprint` | Restarts `python3-validity` + `open-fprintd` on resume so the Synaptics 06cb:009a reader doesn't hang unlock for ~25 s |

## Install

```
sudo cp -r system/etc/. /etc/
sudo cp -r system/usr/. /usr/
sudo chmod +x /usr/lib/systemd/system-sleep/fix-validity-fingerprint
sudo systemctl disable --now open-fprintd-resume.service
```

The last line is one-time cleanup: the stock `open-fprintd-resume.service` tries to call `Resume()` on a stale USB handle after wake and always crashes — our sleep hook replaces it.

## Hardware / OS context

- ThinkPad T480 (Synaptics Validity 06cb:009a fingerprint reader)
- Kubuntu 26.04, KDE Plasma 6, systemd 259
