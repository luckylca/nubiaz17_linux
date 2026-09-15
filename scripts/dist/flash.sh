#!/usr/bin/env bash
# flash.sh — NX563J Ubuntu 一键刷机脚本 (macOS / Linux)
#
# 把手机进 fastboot, 然后在本目录运行:  bash flash.sh
#
# 进 fastboot 的方法:
#   - 关机状态下按住 【音量下 + 电源】 直到出现 fastboot 界面, 或
#   - 系统里运行 /root/reboot-bl
#
# 本脚本只动两个分区: boot 和 userdata (userdata 会被整体覆盖!).
# recovery / recovery2 / 其它分区一律不碰.
set -euo pipefail
cd "$(dirname "$0")"

need() { command -v "$1" >/dev/null 2>&1 || {
  echo "[X] 缺少 $1 — $2" >&2; exit 1; }; }
need fastboot "macOS: brew install android-platform-tools ; Linux: apt install fastboot"

echo "[*] 等待 fastboot 设备出现… (请把手机进 fastboot 并插线)"
until fastboot devices 2>/dev/null | grep -q .; do sleep 2; done
echo "[+] 检测到设备: $(fastboot devices | head -1)"

echo "[*] nubia 刷机闸门 (每个 fastboot 会话必须发一次)"
if ! fastboot oem nubia_unlock NUBIA_NX563J; then
  echo "[!] nubia_unlock 返回非零 (可能本会话已解锁), 继续尝试刷写"
fi

echo "[*] 刷入 boot.img (内核 + initramfs)"
fastboot flash boot boot.img

echo "[*] 解压 userdata 镜像…"
gunzip -kf userdata.img.gz
IMG=userdata.img

echo "[*] 刷入 userdata (raw ext4, 约 $(du -h "$IMG" | cut -f1 | tr -d ' '), 需要几分钟)"
if ! fastboot flash userdata "$IMG"; then
  echo "[!] raw 刷写被拒, 转 Android sparse 格式重试"
  need python3 "sparse 转换需要 python3"
  python3 img2simg.py "$IMG" userdata.sparse.img
  fastboot flash userdata userdata.sparse.img
  rm -f userdata.sparse.img
fi
rm -f "$IMG"

echo "[*] 重启进系统"
fastboot reboot

cat <<'EOF'

[+] 刷机完成。首次启动约 1-2 分钟, 之后:
    - USB 线连电脑, 设备网卡 10.42.0.1, Mac 侧执行
        sudo ifconfig <新en接口> inet 10.42.0.32 netmask 255.255.255.0
      然后 ssh root@10.42.0.1
    - 扩容文件系统到整个 userdata 分区 (镜像只做了最小尺寸):
        ssh root@10.42.0.1 'resize2fs /dev/sda10'
      (在线扩容, 不用重启)
EOF
