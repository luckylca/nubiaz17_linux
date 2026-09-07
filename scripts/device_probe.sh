#!/usr/bin/env bash
set -euo pipefail

ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"

if [[ ! -x "$ADB" ]]; then
  echo "adb not found: $ADB" >&2
  exit 2
fi

if ! "$ADB" get-state >/dev/null 2>&1; then
  echo "No authorized ADB device is currently available." >&2
  "$ADB" devices -l
  exit 3
fi

echo "=== identity ==="
"$ADB" shell 'getprop ro.product.model; getprop ro.product.device; getprop ro.product.board; getprop ro.board.platform; getprop ro.build.fingerprint'

echo "=== boot/security ==="
"$ADB" shell 'getprop ro.boot.verifiedbootstate; getprop ro.boot.flash.locked; getprop ro.boot.vbmeta.device_state; getprop ro.boot.slot_suffix; getprop ro.boot.boot_devices'

echo "=== kernel ==="
"$ADB" shell 'uname -a; cat /proc/cmdline'

echo "=== block devices ==="
"$ADB" shell 'ls -l /dev/block/bootdevice/by-name 2>/dev/null || true; cat /proc/partitions'

echo "=== mounts ==="
"$ADB" shell 'mount'

echo "=== storage ==="
"$ADB" shell 'df -h 2>/dev/null || true'

echo "=== cpu/memory ==="
"$ADB" shell 'cat /proc/cpuinfo | head -80; cat /proc/meminfo | head -40'

echo "=== usb ==="
"$ADB" shell 'getprop sys.usb.config; getprop sys.usb.state; getprop ro.boot.usbcontroller'

echo "=== wlan/bluetooth hints ==="
"$ADB" shell 'getprop | grep -Ei "wifi|wlan|bluetooth|bt\." | head -120 || true'

echo
echo "Probe complete. This script is read-only."
