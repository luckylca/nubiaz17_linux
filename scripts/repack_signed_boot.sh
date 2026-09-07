#!/usr/bin/env bash
set -euo pipefail

# Repack an NX563J Android boot image with a replacement kernel and reproduce
# the legacy /boot signature used by the device. This script only creates a
# local image. It never calls adb, fastboot, dd, or writes a phone partition.
#
# Usage:
#   scripts/repack_signed_boot.sh BASE_BOOT NEW_KERNEL OUTPUT_BOOT [NEW_RAMDISK]
#
# BASE_BOOT may be a full 64 MiB partition dump. The output is the compact,
# signed active boot image suitable for inspection or a later non-destructive
# fastboot-boot test if the bootloader permits it.

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Usage: $0 BASE_BOOT NEW_KERNEL OUTPUT_BOOT [NEW_RAMDISK]" >&2
  exit 2
fi

BASE_BOOT="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
NEW_KERNEL="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
OUTPUT_BOOT="$3"
NEW_RAMDISK="${4:-}"

for f in "$BASE_BOOT" "$NEW_KERNEL"; do
  [[ -f "$f" ]] || { echo "Missing file: $f" >&2; exit 2; }
done
if [[ -n "$NEW_RAMDISK" ]]; then
  NEW_RAMDISK="$(cd "$(dirname "$NEW_RAMDISK")" && pwd)/$(basename "$NEW_RAMDISK")"
  [[ -f "$NEW_RAMDISK" ]] || { echo "Missing ramdisk: $NEW_RAMDISK" >&2; exit 2; }
fi

command -v git >/dev/null
command -v python3 >/dev/null
command -v java >/dev/null

ROOT="$(git rev-parse --show-toplevel)"
WORK="$ROOT/work/boot-tools"
TMP="$ROOT/work/boot-repack"
MKBOOTIMG_REPO="https://android.googlesource.com/platform/system/tools/mkbootimg"
MKBOOTIMG_COMMIT="d2bb0af5ba6d3198a3e99529c97eda1be0b5a093"
SIGNER_REPO="https://github.com/kindle4jerry/boot_signer_for_nubia_nx563j.git"
SIGNER_COMMIT="fa26cf3f625efbb772bb43c81cabd0ab7089a93e"

mkdir -p "$WORK"

ensure_checkout() {
  local dir="$1" repo="$2" commit="$3"
  if [[ ! -d "$dir/.git" ]]; then
    rm -rf "$dir"
    git clone "$repo" "$dir"
  fi
  git -C "$dir" fetch --depth=1 origin "$commit"
  git -C "$dir" checkout --detach "$commit" >/dev/null
  test "$(git -C "$dir" rev-parse HEAD)" = "$commit"
}

ensure_checkout "$WORK/mkbootimg" "$MKBOOTIMG_REPO" "$MKBOOTIMG_COMMIT"
ensure_checkout "$WORK/boot-signer" "$SIGNER_REPO" "$SIGNER_COMMIT"

rm -rf "$TMP"
mkdir -p "$TMP/unpacked"

FORMAT_ARGS="$(
  python3 "$WORK/mkbootimg/unpack_bootimg.py"     --boot_img "$BASE_BOOT"     --out "$TMP/unpacked"     --format=mkbootimg
)"

RAMDISK="$TMP/unpacked/ramdisk"
if [[ -n "$NEW_RAMDISK" ]]; then
  RAMDISK="$NEW_RAMDISK"
fi

export FORMAT_ARGS NEW_KERNEL RAMDISK TMP MKBOOTIMG="$WORK/mkbootimg/mkbootimg.py"
python3 - <<'PY'
import os
import shlex
import subprocess

args = shlex.split(os.environ["FORMAT_ARGS"])
kernel = os.environ["NEW_KERNEL"]
ramdisk = os.environ["RAMDISK"]
out = os.path.join(os.environ["TMP"], "boot-unsigned.img")

def replace_arg(name, value):
    try:
        i = args.index(name)
    except ValueError:
        args.extend([name, value])
    else:
        if i + 1 >= len(args):
            raise SystemExit(f"Malformed unpacked argument list: {name}")
        args[i + 1] = value

replace_arg("--kernel", kernel)
replace_arg("--ramdisk", ramdisk)

cmd = ["python3", os.environ["MKBOOTIMG"], *args, "-o", out]
print("Repacking unsigned boot image")
subprocess.run(cmd, check=True)
PY

# Current AOSP mkbootimg zeroes second_addr when second_size is zero. The
# original NX563J header-v0 image keeps the legacy second_addr (0x00f00000).
# Copy exactly those four header bytes from the baseline before signing.
export BASE_BOOT TMP
python3 - <<'PY'
import os
from pathlib import Path

base = Path(os.environ["BASE_BOOT"]).read_bytes()
out_path = Path(os.environ["TMP"]) / "boot-unsigned.img"
out = bytearray(out_path.read_bytes())

if base[:8] != b"ANDROID!" or out[:8] != b"ANDROID!":
    raise SystemExit("Not an Android boot image")
if len(out) < 32 or len(base) < 32:
    raise SystemExit("Boot image header is truncated")

out[28:32] = base[28:32]
out_path.write_bytes(out)
PY

java -jar "$WORK/boot-signer/boot_signer.jar"   /boot   "$TMP/boot-unsigned.img"   "$WORK/boot-signer/verity.pk8"   "$WORK/boot-signer/verity.x509.pem"   "$TMP/boot-signed.img"

java -jar "$WORK/boot-signer/boot_signer.jar"   -verify "$TMP/boot-signed.img"

mkdir -p "$(dirname "$OUTPUT_BOOT")"
cp "$TMP/boot-signed.img" "$OUTPUT_BOOT"

BASE_SIZE="$(stat -f%z "$BASE_BOOT" 2>/dev/null || stat -c%s "$BASE_BOOT")"
OUT_SIZE="$(stat -f%z "$OUTPUT_BOOT" 2>/dev/null || stat -c%s "$OUTPUT_BOOT")"

if (( OUT_SIZE > BASE_SIZE )); then
  echo "ERROR: generated boot image ($OUT_SIZE) exceeds baseline partition dump size ($BASE_SIZE)" >&2
  exit 1
fi

echo "Generated signed boot image: $OUTPUT_BOOT"
echo "Output size: $OUT_SIZE bytes"
echo "Baseline/partition dump size: $BASE_SIZE bytes"
if command -v shasum >/dev/null; then
  shasum -a 256 "$OUTPUT_BOOT"
else
  sha256sum "$OUTPUT_BOOT"
fi

echo "No device write was performed."
