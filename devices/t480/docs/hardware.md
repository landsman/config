# T480 — hardware

| Component | Detail |
|---|---|
| Model | ThinkPad T480 (20L6S0CE41) |
| CPU | Intel Core i5-8350U |
| GPU | Intel UHD Graphics 620, Kaby Lake-R GT2 `[8086:5917]`, `i915` |
| BIOS | N24ET81W (1.56), 2025-09-06 |
| RAM | 64 GB (`MemTotal` 65583460 kB, ~62 GiB usable) |
| Storage | Samsung SSD 990 EVO Plus 2 TB NVMe (PM9C1a controller, DRAM-less), LUKS-encrypted root |
| Display | 14" IPS FHD — 1920x1080 @60.02 Hz, LG Display (`LGD 1313`, 2016), 31 × 17 cm, sRGB, no VRR/HDR |
| Webcam | Integrated Camera — IMC Networks `13d3:56a6` (UVC), `/dev/video0` capture + `/dev/video1` metadata |
| Fingerprint | Synaptics Validity 06cb:009a |
| Touchpad | Synaptics RMI4 |
| Boot | Triple boot — Kubuntu 26.04 (KDE), Omarchy/Arch (Hyprland), Windows 11 |
| Dock | DisplayPort MST — BenQ 4K 3840x2160 on DP-1 (`BNQ 31056`), Dell 2560x1440 on DP-4 (`DEL 41179`) |

The panel also advertises a 1920x1080 **@48 Hz** mode, which is worth knowing if
battery life ever matters more than smoothness. Backlight is `intel_backlight`,
range 0–1023.

## Operating systems

| OS | Role | Config tracked in |
|----|------|-------------------|
| Kubuntu 26.04 (KDE, Wayland) | Daily driver | [`os/ubuntu/`](../../../os/ubuntu) |
| Omarchy / Arch (Hyprland) | Second Linux | [`os/arch/`](../../../os/arch) |
| Windows 11 | Debugging legacy Windows apps that clients want rewritten | not tracked |

**Nothing is tracked for Windows** and no `os/windows/` package exists. It is a
booted-when-needed environment, and the stow layout is POSIX-shaped anyway — the
OS package is chosen from `/etc/os-release`, which Windows does not have. If
Windows-side config ever needs versioning it wants its own mechanism, not this one.

Windows sharing the disk is worth remembering when touching boot config: the
`GRUB_DEFAULT` pin (see [known issues](issues/internal-panel-black-on-resume.md))
selects a specific kernel entry by title, so a Windows update that reorders or
rewrites the EFI boot entries can invalidate it. Re-check `uname -r` after one.

## Re-reading these values

```
cat /sys/class/dmi/id/product_version    # ThinkPad T480  -> the `devices/` package name
cat /sys/class/dmi/id/product_name       # 20L6S0CE41
cat /sys/class/dmi/id/bios_version
grep MemTotal /proc/meminfo              # RAM
lsblk -dno NAME,SIZE,MODEL | grep nvme   # drive model + size
lspci -nnk -s 00:02.0                    # GPU + driver in use
kscreen-doctor -o                        # current outputs, modes, capabilities (Wayland)
edid-decode /sys/class/drm/card1-eDP-1/edid   # panel vendor + physical size
lsusb | grep -i camera                   # webcam vendor/product id
v4l2-ctl -d /dev/video0 --list-formats-ext    # webcam modes (needs v4l-utils)
```

`make stow` derives the device package name from `product_version`, so the last
word of that string has to match the directory under `devices/`.
