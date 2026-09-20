#!/usr/bin/env bash
# Install the tested ARM64 slirp4netns userspace into the NX563J Kali chroot.
# Host-side helper for macOS. It does not flash or alter the Android kernel.
set -euo pipefail

ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
SER="${SER:-392a99df}"
CHROOT="/data/local/nhsystem/kali-arm64"

LIBSLIRP_URL='https://deb.debian.org/debian/pool/main/libs/libslirp/libslirp0_4.9.4-1_arm64.deb'
SLIRP_URL='https://deb.debian.org/debian/pool/main/s/slirp4netns/slirp4netns_1.3.3-1+b1_arm64.deb'
LIBSLIRP_SHA='2c541b8a96a91ac9f0520b93eceddb574540e021a2ab5a710c4aa809f00902c8'
SLIRP_SHA='0255695cc98277f249345795c3e4c8b76be6d36793f31808548a09ef23b7c660'

adb() { "$ADB" -s "$SER" "$@"; }
rootsh() {
  local encoded
  encoded="$(printf '%s' "$1" | base64 | tr -d '\n')"
  adb shell "su -c 'echo $encoded | /data/adb/magisk/busybox base64 -d | /system/bin/sh'"
}

TMP="$(mktemp -d /tmp/nx563j-slirp.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

echo '==> download tested ARM64 packages'
curl -L --fail --silent --show-error -o "$TMP/libslirp0.deb" "$LIBSLIRP_URL"
curl -L --fail --silent --show-error -o "$TMP/slirp4netns.deb" "$SLIRP_URL"

echo '==> verify SHA256'
echo "$LIBSLIRP_SHA  $TMP/libslirp0.deb" | shasum -a 256 -c -
echo "$SLIRP_SHA  $TMP/slirp4netns.deb" | shasum -a 256 -c -

echo '==> push into Kali chroot tmp'
adb push "$TMP/libslirp0.deb" /data/local/tmp/libslirp0.deb >/dev/null
adb push "$TMP/slirp4netns.deb" /data/local/tmp/slirp4netns.deb >/dev/null
rootsh "/data/adb/magisk/busybox cp /data/local/tmp/libslirp0.deb $CHROOT/tmp/libslirp0.deb; /data/adb/magisk/busybox cp /data/local/tmp/slirp4netns.deb $CHROOT/tmp/slirp4netns.deb"

echo '==> install in Kali'
CMD='PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; export PATH; dpkg -i /tmp/libslirp0.deb /tmp/slirp4netns.deb; slirp4netns --version'
ENC="$(printf '%s' "$CMD" | base64 | tr -d '\n')"
rootsh "/data/adb/magisk/busybox chroot $CHROOT /bin/sh -c 'echo $ENC | /bin/base64 -d | /bin/sh'"

echo 'NX563J_SLIRP4NETNS_INSTALL_PASS'
