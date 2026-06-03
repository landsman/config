# internet speed test
alias speed='cloudflare-speed-cli'
alias fast='speed'

# thinkpad gpu tui (sudo apt install intel-gpu-tools / sudo pacman -S intel-gpu-tools)
alias gpu='sudo intel_gpu_top'

# thinkpad cpu temps + fan watch (T480 thermal monitoring)
alias temps='watch -n2 "sensors | grep -E \"Package|Core|fan\"; cat /proc/acpi/ibm/fan | head -3"'
