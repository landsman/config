# T480 hardware aliases — same on every OS installed on this laptop.
# Tools: intel-gpu-tools, lm-sensors, s-tui
#   Ubuntu: sudo apt install intel-gpu-tools lm-sensors s-tui
#   Arch:   sudo pacman -S intel-gpu-tools lm_sensors s-tui
# Not in the Brewfile: all three read Linux-only interfaces (i915 debugfs,
# hwmon, RAPL), so they stay with the distro.

# intel gpu tui
alias gpu='sudo intel_gpu_top'

# cpu temps + fan watch (needs thinkpad_acpi -> /proc/acpi/ibm/fan)
alias temps='watch -n2 "sensors | grep -E \"Package|Core|fan\"; cat /proc/acpi/ibm/fan | head -3"'

# same numbers as a graph over time, plus a built-in stress test — the thing to
# watch when checking whether the RAPL cap and undervolt actually hold under
# load. Root, or the power column stays empty (RAPL needs privileges).
# https://github.com/amanusk/s-tui
alias stui='sudo s-tui'
