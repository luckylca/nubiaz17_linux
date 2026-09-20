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
#   Server Watch    <- current server-watch source is built + installed on
#                      the phone BEFORE the snapshot, so the default package
#                      always contains the latest Full Dashboard UI + agent
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
BOOTIMG="$ROOT/work/docker-kernel-repack/boot-0013-final-signed.img"
DEST="$ROOT/work/dist/nx563j-ubuntu-$VER"
SSH="ssh -o ConnectTimeout=8 root@10.42.0.1"
DEV_SRC=/proc/1/root/mnt/rootfs   # userdata root, seen from the Ubuntu chroot
DEV_BUILD=/root/dist-build        # on userdata: <rootfs>/ubuntu/root/dist-build

[[ -f "$BOOTIMG" ]] || { echo "missing $BOOTIMG" >&2; exit 1; }
command -v ssh >/dev/null

echo "[1/8] device reachable?"
$SSH "echo ok: \$(uname -r)" || { echo "device unreachable" >&2; exit 1; }

echo "[2/8] install current Server Watch into live rootfs"
SERVER_WATCH_DIR="$ROOT/server-watch"
[[ -x "$SERVER_WATCH_DIR/scripts/deploy.sh" ]] || {
  echo "missing Server Watch deploy script: $SERVER_WATCH_DIR/scripts/deploy.sh" >&2
  exit 1
}
PHONE=10.42.0.1 KEY="$ROOT/work/nx563j_key" \
  "$SERVER_WATCH_DIR/scripts/deploy.sh"

echo "[3/8] verify running boot partition == $(basename "$BOOTIMG")"
IMG_SIZE=$(stat -f%z "$BOOTIMG" 2>/dev/null || stat -c%s "$BOOTIMG")
# Partition-truncated hash convention (RESEARCH.md): the tail <512 bytes of
# the signed image can differ from partition residue, so both sides hash
# only the first floor(size/512)*512 bytes.
IMG_SHA=$(dd if="$BOOTIMG" bs=512 count=$((IMG_SIZE/512)) 2>/dev/null | shasum -a 256 | awk '{print $1}')
DEV_SHA=$($SSH "dd if=/dev/block/bootdevice/by-name/boot bs=512 count=$((IMG_SIZE/512)) 2>/dev/null | sha256sum" | awk '{print $1}')
echo "    img $IMG_SHA"
echo "    dev $DEV_SHA"
[[ "$IMG_SHA" == "$DEV_SHA" ]] || {
  echo "[X] device boot partition does not match $BOOTIMG — refusing to" >&2
  echo "    package a boot image the device is not actually running." >&2
  exit 1; }

mkdir -p "$DEST"
cp "$BOOTIMG" "$DEST/boot.img"

echo "[4/8] build userdata ext4 image on device"
# userdata root = Alpine base + /ubuntu + /boot-target + ~20GB legacy
# Android /data junk (app/data/media/dalvik-cache/...). Package only what
# the boot chain needs — include list, not exclude list.
# Runtime-regenerated caches (fwimage, /system+apex bind targets, var/log,
# tmp, caches) ship EMPTY — wifi-bringup4.sh re-creates/re-populates them
# (mkdir -p + mount from sde10). NOTE 2026-09-19: sda9 (原 Android /system)
# 已被 LOS 覆盖作废, /system 现在由 userdata 自带的 ubuntu/system-min 提供
# (A9 stock bionic 库) —— system-min 必须随包发布, 不在排除列表里。
INCLUDES="boot-target ubuntu bin etc home lib local media mnt opt root run \
sbin srv tmp usr var dev proc sys bt_firmware sdcard"
EXCLUDES="ubuntu/system/* ubuntu/apex/* ubuntu/fwimage/* ubuntu/vendor/* \
ubuntu/tmp/* ubuntu/run/* ubuntu/var/log/* ubuntu/var/cache/* \
ubuntu/root/.cache/* ubuntu/root/dist-build/* var/log/* tmp/* run/* media/*"
read -r -a INC_ARR <<< "$INCLUDES"
EXC_ARGS=(); for e in $EXCLUDES; do EXC_ARGS+=(--exclude="$e"); done
# size the exact tar stream first (one pass), then image = stream*1.25+512MB
STREAM_MB=$($SSH "tar -C $DEV_SRC --numeric-owner --one-file-system \
  ${EXC_ARGS[*]} --warning=no-file-changed -cf - $INCLUDES 2>/dev/null | wc -c")
STREAM_MB=$(( STREAM_MB / 1048576 + 1 ))
IMG_MB=$(( STREAM_MB * 5 / 4 + 512 ))
echo "    payload ${STREAM_MB}MB -> image ${IMG_MB}MB (sparse)"
$SSH "set -e
  umount /mnt/dist-img 2>/dev/null || true
  rm -rf $DEV_BUILD && mkdir -p $DEV_BUILD
  dd if=/dev/zero of=$DEV_BUILD/userdata.img bs=1M count=0 seek=$IMG_MB
  mkfs.ext4 -F -m 0 -L userdata $DEV_BUILD/userdata.img >/dev/null
  mkdir -p /mnt/dist-img
  mount -o loop $DEV_BUILD/userdata.img /mnt/dist-img
  date > /mnt/dist-img/dist-snapshot; echo 'nx563j-ubuntu-$VER' >> /mnt/dist-img/dist-snapshot
  tar -C $DEV_SRC --numeric-owner --one-file-system \
      ${EXC_ARGS[*]} --warning=no-file-changed \
      -cf - $INCLUDES | tar -C /mnt/dist-img --numeric-owner -xf -
  mkdir -p /mnt/dist-img/ubuntu/system /mnt/dist-img/ubuntu/apex/com.android.runtime \
           /mnt/dist-img/ubuntu/fwimage /mnt/dist-img/ubuntu/vendor \
           /mnt/dist-img/ubuntu/tmp /mnt/dist-img/ubuntu/run \
           /mnt/dist-img/ubuntu/var/log /mnt/dist-img/ubuntu/var/cache \
           /mnt/dist-img/var/log /mnt/dist-img/tmp /mnt/dist-img/run
  sync; umount /mnt/dist-img
  echo IMAGE_BUILT"

echo "[5/8] stream image back (gzip) — this takes a while"
$SSH "gzip -1 < $DEV_BUILD/userdata.img" > "$DEST/userdata.img.gz"
$SSH "rm -rf $DEV_BUILD"
ls -lh "$DEST/userdata.img.gz"

echo "[6/8] package scripts"
cp "$ROOT/scripts/dist/flash.sh" "$ROOT/scripts/dist/README.md" "$DEST/"
cp "$ROOT/tools/simg/img2simg.py" "$DEST/"

echo "[7/8] manifest"
{
  echo "nx563j-ubuntu-$VER"
  echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "device uname: $($SSH 'uname -a')"
  echo "boot.img sha256 (full): $(shasum -a 256 "$BOOTIMG" | awk '{print $1}')"
  echo "boot.img sha256 (512-trunc, = running partition): $IMG_SHA"
  echo "userdata.img.gz sha256: $(shasum -a 256 "$DEST/userdata.img.gz" | awk '{print $1}')"
  echo "server-watch: bundled from current source before snapshot"
  echo "server-watch source commit: $(git -C "$ROOT" rev-parse HEAD)"
  echo "userdata payload: ${STREAM_MB}MB (of ~30GB used; legacy Android /data excluded), image: ${IMG_MB}MB"
  echo "excluded by design: Android /data legacy (app,data,media,dalvik-cache,...),"
  echo "  /ubuntu/system+apex+fwimage (runtime re-staged from sde10), logs, caches;"
  echo "packaging commit: $(git -C "$ROOT" rev-parse HEAD)"
} > "$DEST/MANIFEST.txt"
$SSH "chroot /proc/1/root/mnt/rootfs/ubuntu dpkg -l 2>/dev/null || dpkg -l" \
  > "$DEST/MANIFEST-dpkg.txt" || true

echo "[8/8] tarball"
tar -C "$ROOT/work/dist" -czf "$ROOT/work/dist/nx563j-ubuntu-$VER.tar.gz" "nx563j-ubuntu-$VER"
ls -lh "$ROOT/work/dist/nx563j-ubuntu-$VER.tar.gz"

echo
echo "DONE: $DEST"
echo "Optional end-to-end selftest (WIPES and restores the phone):"
echo "  cd $DEST && bash flash.sh"
