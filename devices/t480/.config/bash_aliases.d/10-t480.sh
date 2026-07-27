# T480 hardware aliases — same on every OS installed on this laptop.
# Tools: intel-gpu-tools, lm-sensors
#   Ubuntu: sudo apt install intel-gpu-tools lm-sensors
#   Arch:   sudo pacman -S intel-gpu-tools lm_sensors

# intel gpu tui
alias gpu='sudo intel_gpu_top'

# cpu temps + fan watch (needs thinkpad_acpi -> /proc/acpi/ibm/fan)
alias temps='watch -n2 "sensors | grep -E \"Package|Core|fan\"; cat /proc/acpi/ibm/fan | head -3"'
