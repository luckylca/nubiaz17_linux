#!/usr/bin/env bash
# make_dist.sh — snapshot the live NX563J Ubuntu system into a fastboot
# one-click package under work/dist/nx563j-ubuntu-<VER>/.
#
# What gets packaged:
#   boot.img        <- $BOOTIMG (must match the device's running boot
#                      partition; verified by hash before snapshotting)
#   userdata.img.gz <- ext4 image of the WHOLE userdata fs (Alpine base +
#                      /ubuntu + /boot-target), built on-device with
#                      mkfs.ext4 + loop + tar, gzip-streamed back
#   flash.sh / README.md / img2simg.py  <- scripts/dist/, tools/simg/
#   MANIFEST.txt    <- versions, hashes, dpkg list
#
# Prerequisites: ssh root@10.42.0.1 reachable (USB gadget up), device
# booted into the system being snapshotted. Snapshot is of a LIVE fs —
# keep the device idle during the run.
#
# Usage: scripts/make_dist.sh [VER]          (default VER=$(date +%Y%m%d))
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VER="${1:-$(date +%Y%m%d)}"
BOOTIMG="$ROOT/work/boot-nethunter-daily2.img"
DEST="$ROOT/work/dist/nx563j-ubuntu-$VER"
SSH="ssh -o ConnectTimeout=8 root@10.42.0.1"
DEV_SRC=/proc/1/root/mnt/rootfs   # userdata root, seen from the Ubuntu chroot
DEV_BUILD=/root/dist-build        # on userdata: <rootfs>/ubuntu/root/dist-build

[[ -f "$BOOTIMG" ]] || { echo "missing $BOOTIMG" >&2; exit 1; }
command -v ssh >/dev/null

echo "[1/7] device reachable?"
$SSH "echo ok: \$(uname -r)" || { echo "device unreachable" >&2; exit 1; }

echo "[2/7] verify running boot partition == $(basename "$BOOTIMG")"
IMG_SIZE=$(stat -f%z "$BOOTIMG")
IMG_SHA=$(shasum -a 256 "$BOOTIMG" | awk '{print $1}')
DEV_SHA=$($SSH "dd if=/dev/block/bootdevice/by-name/boot bs=512 count=$((IMG_SIZE/512)) 2>/dev/null | sha256sum" | awk '{print $1}')
echo "    img $IMG_SHA"
echo "    dev $DEV_SHA"
[[ "$IMG_SHA" == "$DEV_SHA" ]] || {
  echo "[X] device boot partition does not match $BOOTIMG — refusing to" >&2
  echo "    package a boot image the device is not actually running." >&2
  exit 1; }

mkdir -p "$DEST"
cp "$BOOTIMG" "$DEST/boot.img"

echo "[3/7] build userdata ext4 image on device"
USED_MB=$($SSH "df -m /dev/sda10 | awk 'NR==2{print \$3}'")
IMG_MB=$(( USED_MB * 4 / 3 + 512 ))
echo "    userdata used ${USED_MB}MB -> image ${IMG_MB}MB (sparse)"
$SSH "set -e
  rm -rf $DEV_BUILD && mkdir -p $DEV_BUILD
  dd if=/dev/zero of=$DEV_BUILD/userdata.img bs=1M count=0 seek=$IMG_MB
  mkfs.ext4 -F -m 0 -L userdata $DEV_BUILD/userdata.img >/dev/null
  mkdir -p /mnt/dist-img
  mount -o loop $DEV_BUILD/userdata.img /mnt/dist-img
  date > /mnt/dist-img/dist-snapshot; echo 'nx563j-ubuntu-$VER' >> /mnt/dist-img/dist-snapshot
  tar -C $DEV_SRC --numeric-owner --one-file-system \
      --exclude=./lost+found \
      --exclude=./ubuntu/root/dist-build \
      --exclude=./ubuntu/tmp \
      --exclude=./ubuntu/run \
      --exclude=./ubuntu/var/cache/apt/archives \
      --exclude=./ubuntu/root/.cache \
      -cf - . | tar -C /mnt/dist-img --numeric-owner -xf -
  mkdir -p /mnt/dist-img/ubuntu/tmp /mnt/dist-img/ubuntu/run
  sync; umount /mnt/dist-img
  echo IMAGE_BUILT"

echo "[4/7] stream image back (gzip) — this takes a while"
$SSH "gzip -1 < $DEV_BUILD/userdata.img" > "$DEST/userdata.img.gz"
$SSH "rm -rf $DEV_BUILD"
ls -lh "$DEST/userdata.img.gz"

echo "[5/7] package scripts"
cp "$ROOT/scripts/dist/flash.sh" "$ROOT/scripts/dist/README.md" "$DEST/"
cp "$ROOT/tools/simg/img2simg.py" "$DEST/"

echo "[6/7] manifest"
{
  echo "nx563j-ubuntu-$VER"
  echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "device uname: $($SSH 'uname -a')"
  echo "boot.img sha256: $IMG_SHA  (= running boot partition)"
  echo "userdata.img.gz sha256: $(shasum -a 256 "$DEST/userdata.img.gz" | awk '{print $1}')"
  echo "userdata used: ${USED_MB}MB, image: ${IMG_MB}MB"
  echo "packaging commit: $(git -C "$ROOT" rev-parse HEAD)"
} > "$DEST/MANIFEST.txt"
$SSH "chroot /proc/1/root/mnt/rootfs/ubuntu dpkg -l 2>/dev/null || dpkg -l" \
  > "$DEST/MANIFEST-dpkg.txt" || true

echo "[7/7] tarball"
tar -C "$ROOT/work/dist" -czf "$ROOT/work/dist/nx563j-ubuntu-$VER.tar.gz" "nx563j-ubuntu-$VER"
ls -lh "$ROOT/work/dist/nx563j-ubuntu-$VER.tar.gz"

echo
echo "DONE: $DEST"
echo "Optional end-to-end selftest (WIPES and restores the phone):"
echo "  cd $DEST && bash flash.sh"
