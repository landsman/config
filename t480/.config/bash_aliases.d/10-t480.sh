# T480-specific aliases — depend on Intel graphics and thinkpad_acpi.

# intel gpu tui (sudo apt install intel-gpu-tools)
alias gpu='sudo intel_gpu_top'

# cpu temps + fan watch (needs thinkpad_acpi -> /proc/acpi/ibm/fan)
alias temps='watch -n2 "sensors | grep -E \"Package|Core|fan\"; cat /proc/acpi/ibm/fan | head -3"'
