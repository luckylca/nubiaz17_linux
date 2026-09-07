#!/usr/bin/env bash
set -euo pipefail

# Assemble a signed NX563J diagnostic boot image:
#   kernel  = downstream Image.gz-dtb (or a diag-config CI build of it)
#   ramdisk = the diagnostic initramfs from scripts/build_diag_initramfs.sh
#   header  = original NX563J geometry, via scripts/repack_signed_boot.sh
#
# Usage:
#   scripts/build_diag_boot.sh IMAGE_GZ_DTB OUTPUT_IMG [BASE_BOOT]
#
# BASE_BOOT defaults to the verified baseline dump. This script only creates
# a local image; it never touches the phone.

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 IMAGE_GZ_DTB OUTPUT_IMG [BASE_BOOT]" >&2
  exit 2
fi

ROOT="$(git rev-parse --show-toplevel)"
KERNEL="$1"
OUTPUT="$2"
BASE="${3:-$ROOT/backups/2026-09-07-baseline/boot.img}"
INITRAMFS="$ROOT/work/diag-initramfs/diag-initramfs.cpio.gz"

[[ -f "$KERNEL" ]] || { echo "Missing kernel: $KERNEL" >&2; exit 2; }
[[ -f "$BASE" ]] || { echo "Missing baseline boot: $BASE" >&2; exit 2; }

if [[ ! -f "$INITRAMFS" ]]; then
  echo "Building diagnostic initramfs first"
  "$ROOT/scripts/build_diag_initramfs.sh"
fi

"$ROOT/scripts/repack_signed_boot.sh" "$BASE" "$KERNEL" "$OUTPUT" "$INITRAMFS"
