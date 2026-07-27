# T480 — hardware

| | |
|---|---|
| Model | ThinkPad T480 (20L6S0CE41) |
| CPU | Intel Core i5-8350U |
| GPU | Intel UHD Graphics 620, Kaby Lake-R GT2 `[8086:5917]`, `i915` |
| BIOS | N24ET81W (1.56), 2025-09-06 |
| Storage | Samsung PM9C1a NVMe, LUKS-encrypted root |
| Fingerprint | Synaptics Validity 06cb:009a |
| Dual boot | Kubuntu 26.04 (KDE) and Omarchy/Arch (Hyprland) |
| Dock | DisplayPort MST — BenQ 4K on DP-1, second panel on DP-4 |

## Re-reading these values

```
cat /sys/class/dmi/id/product_version    # ThinkPad T480  -> the `devices/` package name
cat /sys/class/dmi/id/product_name       # 20L6S0CE41
cat /sys/class/dmi/id/bios_version
lspci -nnk -s 00:02.0                    # GPU + driver in use
kscreen-doctor -o                        # current outputs (Wayland)
```

`make stow` derives the device package name from `product_version`, so the last
word of that string has to match the directory under `devices/`.
