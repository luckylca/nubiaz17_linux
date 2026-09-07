#!/usr/bin/env bash
set -euo pipefail

# Read-only fastboot inventory for Nubia Z17 / NX563J.
#
# This script intentionally does NOT contain any partition write, erase,
# unlock, format, set_active, reboot, boot-image upload, or OEM unlock command.
# Its purpose is to resolve bootloader/security state before any Linux test.
#
# Optional:
#   FASTBOOT=/absolute/path/to/fastboot scripts/fastboot_readonly_probe.sh

FASTBOOT="${FASTBOOT:-fastboot}"

if ! command -v "$FASTBOOT" >/dev/null 2>&1 && [[ ! -x "$FASTBOOT" ]]; then
  echo "fastboot not found: $FASTBOOT" >&2
  exit 2
fi

echo "=== fastboot devices ==="
devices="$("$FASTBOOT" devices -l 2>/dev/null || true)"
printf '%s\n' "$devices"

if [[ -z "${devices//[[:space:]]/}" ]]; then
  echo "No fastboot device detected." >&2
  exit 1
fi

getvar() {
  local name="$1"
  echo
  echo "=== getvar $name ==="
  # fastboot prints getvar replies to stderr on many versions.
  "$FASTBOOT" getvar "$name" 2>&1 || true
}

vars=(
  product
  variant
  version-bootloader
  version-baseband
  serialno
  secure
  unlocked
  off-mode-charge
  current-slot
  slot-count
  slot-suffixes
  has-slot:boot
  max-download-size
  partition-size:boot
  partition-type:boot
)

for var in "${vars[@]}"; do
  getvar "$var"
done

echo
echo "Read-only probe complete."
echo "No boot, flash, erase, format, unlock, set_active, or reboot command was issued."
