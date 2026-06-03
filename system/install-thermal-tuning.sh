#!/usr/bin/env bash
# Install thermal tuning stack for ThinkPad T480 (i5-8350U, dual heatpipe):
#   - thinkfan with a balanced fan curve
#   - RAPL PL1 cap at 20 W + max CPU freq cap at 2.5 GHz (systemd unit)
#   - intel-undervolt with Core/Cache -100 mV, GPU -50 mV (built from source,
#     systemd unit handles boot + resume re-apply)
#
# Idempotent: safe to re-run. Run from the repo root or from system/.
#
#   sudo bash system/install-thermal-tuning.sh

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "must run as root (sudo)" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYS="$REPO_ROOT/system"

echo "==> [1/6] Installing packages (thinkfan, build deps)"
apt-get update -qq
apt-get install -y --no-install-recommends \
  thinkfan \
  build-essential \
  pkg-config \
  libcap-dev \
  libsystemd-dev \
  git \
  cpufrequtils \
  linux-cpupower

echo "==> [2/6] Copying configs to /etc"
install -Dm644 "$SYS/etc/modprobe.d/thinkpad_acpi.conf"             /etc/modprobe.d/thinkpad_acpi.conf
install -Dm644 "$SYS/etc/thinkfan.conf"                              /etc/thinkfan.conf
install -Dm644 "$SYS/etc/intel-undervolt.conf"                       /etc/intel-undervolt.conf
install -Dm644 "$SYS/etc/systemd/system/thinkpad-power-tune.service" /etc/systemd/system/thinkpad-power-tune.service

echo "==> [3/6] Reloading thinkpad_acpi to pick up fan_control=1"
modprobe -r thinkpad_acpi || true
modprobe thinkpad_acpi

echo "==> [4/6] Building & installing intel-undervolt from source"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
git clone --depth=1 https://github.com/kitsunyan/intel-undervolt.git "$BUILD_DIR"
(
  cd "$BUILD_DIR"
  ./configure --enable-systemd --unitdir=/usr/lib/systemd/system
  make
  make install
)
# `make install` overwrites /etc/intel-undervolt.conf with upstream default,
# so re-copy ours on top.
install -Dm644 "$SYS/etc/intel-undervolt.conf" /etc/intel-undervolt.conf

echo "==> [5/6] Enabling services"
modprobe msr
systemctl daemon-reload
systemctl enable --now thinkfan.service thinkpad-power-tune.service intel-undervolt.service

echo "==> [6/6] Verification"
echo "--- PL1 (should be 20000000) ---"
cat /sys/class/powercap/intel-rapl/intel-rapl:0/constraint_0_power_limit_uw
echo "--- Max freq (should be 2.50 GHz) ---"
cpupower frequency-info | grep -E "policy"
echo "--- Undervolt (Core/Cache should be -99.61 mV, GPU -49.80 mV) ---"
intel-undervolt read
echo "--- Fan (level should be 0-7 or disengaged, not 'auto') ---"
cat /proc/acpi/ibm/fan | head -3

echo
echo "Done. After reboot, all settings persist. Re-run this script anytime to re-sync."
