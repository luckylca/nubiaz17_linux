#!/bin/sh
# flash-boot-in-system.sh — 在 Ubuntu 系统内直接写 boot 分区（不走 fastboot）。
# 背景：reboot-bl 会 wedge USB（RESEARCH.md 2026-09-18），fastboot 通道不可靠。
#
# ⚠️ 本脚本执行 dd 写 /dev/block/bootdevice/by-name/boot，
#    属于「需用户明确授权」操作，跑之前必须得到用户口头确认。
#
# 用法（Mac 端）:
#   cat boot-new.img | ssh root@10.42.0.1 'sh /root/flash-boot-in-system.sh'
# 脚本先读到 /tmp、校验大小和魔数，写入后读回比对 SHA256，全部一致才重启。
set -e
IMG=/tmp/boot-new.img
BOOT=/dev/block/bootdevice/by-name/boot

cat > $IMG
SZ=$(stat -c %s $IMG)
echo "received $SZ bytes"
# boot 分区 64MB; 镜像必须 <= 分区且是 ANDROID! 魔数
[ "$SZ" -le 67108864 ] || { echo "FAIL: too big"; exit 1; }
[ "$(dd if=$IMG bs=8 count=1 2>/dev/null)" = "ANDROID!" ] || { echo "FAIL: bad magic"; exit 1; }
WANT=$(sha256sum $IMG | cut -d' ' -f1)

dd if=$IMG of=$BOOT bs=4096 conv=fsync
sync
GOT=$(dd if=$BOOT bs=4096 count=$(( (SZ+4095)/4096 )) 2>/dev/null | head -c $SZ | sha256sum | cut -d' ' -f1)
echo "want $WANT"
echo "got  $GOT"
[ "$WANT" = "$GOT" ] || { echo "FAIL: verify mismatch, NOT rebooting"; exit 1; }
echo "FLASH_OK — reboot in 5s (echo b > sysrq)"
sleep 5
echo b > /proc/sysrq-trigger
